import core.bitop;
import core.memory;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.stdio;
import std.string;

immutable static int LET = 26;
immutable static int LET_BITS = 5;
immutable static int LET_MASK = (1 << LET_BITS) - 1;
immutable static int NA = -1;

static assert ((LET + 1) <= (1 << LET_BITS));

string [] read_all_lines (const string file_name)
{
	string [] res;
	auto fin = File (file_name, "rt");
	foreach (w; fin.byLine ())
	{
		res ~= to !(string) (w);
	}
	return res;
}

struct BoardCell
{
	immutable static int WILDCARD_SHIFT = LET_BITS;
	immutable static int ACTIVE_SHIFT = LET_BITS + 1;
	immutable static byte NONE = LET;

	byte contents = NONE;

	alias contents this;

	static assert (ACTIVE_SHIFT < contents.sizeof * 8);

	byte letter () @property const
	{
		return contents & LET_MASK;
	}

	byte letter (const byte new_letter) @property
	{
		contents = (contents & ~LET_MASK) | new_letter;
		return new_letter;
	}

	bool wildcard () @property const
	{
		return (contents & (1 << WILDCARD_SHIFT)) != 0;
	}

	byte wildcard (const byte new_wildcard) @property
	{
		contents = to !(byte) ((contents & ~(1 << WILDCARD_SHIFT)) |
		    (new_wildcard << WILDCARD_SHIFT));
		return new_wildcard;
	}

	bool active () @property const
	{
		return (contents & (1 << ACTIVE_SHIFT)) != 0;
	}

	byte active (const byte new_active) @property
	{
		contents = to !(byte) ((contents & ~(1 << ACTIVE_SHIFT)) |
		    (new_active << ACTIVE_SHIFT));
		return new_active;
	}

	string toString () const
	{
		string res;
		if (contents == NONE)
		{
			res ~= '.';
		}
		else
		{
// BUG! fixed in GIT HEAD
//			res ~= to !(char) (letter + (wildcard ? 'a' : 'A'));
			res ~= to !(dchar) (letter + (wildcard ? 'a' : 'A'));
		}
		return res;
	}
}

struct Board
{
	immutable static int SIZE = 15;

	BoardCell [SIZE] [SIZE] contents;
	int score;
	bool is_flipped;

	alias contents this;

	void flip ()
	{
		foreach (i; 0..SIZE - 1)
		{
			foreach (j; i + 1..SIZE)
			{
				swap (contents[i][j], contents[j][i]);
			}
		}
		is_flipped ^= true;
	}

	string toString () const
	{
		string res;
		foreach (line; contents)
		{
			foreach (cell; line)
			{
				res ~= cell.toString ();
			}
			res ~= '\n';
		}
		res ~= to !(string) (score) ~ ' ';
		res ~= to !(string) (is_flipped) ~ '\n';
		return res;
	}
}

class Scoring
{
	enum Bonus: byte {NO, DW, TW, DL, TL, SIZE};
	immutable static string [Bonus.SIZE] BONUS_NAME =
	    ["--", "DW", "TW", "DL", "TL"];

	Bonus [Board.SIZE] [Board.SIZE] board_bonus;
	int [LET + 1] tile_value;
	int bingo;

	void load_board_bonus (const string file_name)
	{
		string [] line_list = read_all_lines (file_name);
		enforce (line_list.length == Board.SIZE);
		foreach (i, line; line_list)
		{
			auto cur = line.split ();
			enforce (cur.length == Board.SIZE);
			foreach (j, word; cur)
			{
				bool found = false;
				foreach (b; 0..Bonus.SIZE)
				{
					if (word == BONUS_NAME[b])
					{
						board_bonus[i][j] =
						    to !(Bonus) (b);
						found = true;
						break;
					}
				}
				enforce (found);
			}
		}
		debug {writeln ("Scoring: loaded board bonus from ",
		    file_name);}
	}

	void load_tile_values (const string file_name)
	{
		string [] line_list = read_all_lines (file_name);
		enforce (line_list.length == tile_value.length);
		tile_value[] = NA;
		foreach (line; line_list)
		{
			auto cur = line.split ();
			int i = void;
			enforce (cur[0].length == 1);
			if (cur[0][0] == '-')
			{
				i = LET;
			}
			else
			{
				enforce ('A' <= cur[0][0] && cur[0][0] <= 'Z');
				i = cur[0][0] - 'A';
			}
			enforce (tile_value[i] == NA);
			tile_value[i] = to !(int) (cur[1]);
		}
		debug {writeln ("Scoring: loaded tile values from ",
		    file_name);}
	}

	this ()
	{
		load_board_bonus ("data/board-bonus.txt");
		load_tile_values ("data/tile-values.txt");
		bingo = 50;
	}

	void account (ref int score, ref int mult, const BoardCell cur,
	    const int row, const int col)
	{
		int temp = cur.wildcard ? 0 : tile_value[cur.letter];
		if (cur.active)
		{
			final switch (board_bonus[row][col])
			{
				case Bonus.NO:
					break;
				case Bonus.DL:
					temp *= 2;
					break;
				case Bonus.TL:
					temp *= 3;
					break;
				case Bonus.DW:
					mult *= 2;
					break;
				case Bonus.TW:
					mult *= 3;
					break;
				case Bonus.SIZE:
					assert (false);
			}
		}
		score += temp;
	}
}

struct TrieNode
{
	int start;
	int mask;

	static assert (mask.sizeof * 8 >= LET + 1);

	bool word () @property const
	{
		return (mask & (1 << LET)) != 0;
	}

	bool word (const bool new_word) @property
	{
		mask = (mask & ~(1 << LET)) | (new_word << LET);
		return new_word;
	}
}

class Trie
{
	immutable static int NA = -1;
	immutable static int ROOT = 0;
	immutable static char BASE = 'a';

	TrieNode [] contents;

	int next (const int pos, const int ch) const
	{
		int cur_mask = contents[pos].mask;
		if (!(cur_mask & (1 << ch)))
		{
			return NA;
		}
		return contents[pos].start +
		       popcnt (cur_mask & ((1 << ch) - 1));
	}

	this (const char [] [] word_list, const int size_hint = 1)
	{
		int nw = to !(int) (word_list.length);
		enforce (isSorted (word_list));
		contents = [TrieNode ()];
		contents.reserve (size_hint);
		auto vp = new int [nw];
		vp[] = ROOT;
		int old_size = 0;
		int total_length = 0;

		foreach (pos; 0..Board.SIZE)
		{
			foreach (i, w; word_list)
			{
				if (pos < w.length)
				{
					contents[vp[i]].mask |=
					    1 << (w[pos] - BASE);
				}
			}

			int new_size = contents.length;
			foreach (j; old_size..new_size)
			{
				contents[j].start = contents.length;
				contents.length += popcnt (contents[j].mask);
			}
			old_size = new_size;

			foreach (i, w; word_list)
			{
				if (pos < w.length)
				{
					vp[i] = next (vp[i], w[pos] - BASE);
					assert (vp[i] != NA);
					if (pos + 1 == w.length)
					{
						contents[vp[i]].word = true;
						total_length += w.length;
					}
	                	}
			}
		}
		debug {writeln ("Trie: loaded ", nw, " words of total length ",
		    total_length, ", created ", contents.length, " nodes");}
	}
}

struct RackEntry
{
	immutable static ubyte NONE = 0xFF;

	ubyte contents = NONE;

	alias contents this;
	
	ubyte letter () @property const
	{
		return contents & LET_MASK;
	}

	ubyte letter (const ubyte new_letter) @property
	{
		contents = (contents & ~LET_MASK) | new_letter;
		return new_letter;
	}

	ubyte num () @property const
	{
		return contents >> LET_BITS;
	}

	ubyte num (const ubyte new_num) @property
	{
		contents = to !(ubyte) ((contents & LET_MASK) |
		    (new_num << LET_BITS));
		return new_num;
	}

	void inc ()
	{
		contents += (1 << LET_BITS);
	}

	void dec ()
	{
		contents -= (1 << LET_BITS);
	}
}

struct Rack
{
	immutable static int MAX_SIZE = 7;

	RackEntry [MAX_SIZE] contents;
	byte total;

	void add (const byte letter)
	{
		int i = 0;
		while ((contents[i] != RackEntry.NONE) &&
		    (contents[i].letter < letter))
		{
			i++;
		}
		if (contents[i].letter == letter)
		{
			contents[i].inc ();
		}
		else
		{
			int j = MAX_SIZE - 2;
			while ((j > 0) && (contents[j] == RackEntry.NONE))
			{
				j--;
			}
			while (j >= i)
			{
				contents[j + 1] = contents[j];
				j--;
			}
			contents[i] = cast (ubyte) (letter + (1 << LET_BITS));
		}
		total++;
	}

	void normalize ()
	{
		int i = 0;
		int j = 0;
		total = 0;
		while (i < MAX_SIZE &&
		    contents[i] != RackEntry.NONE)
		{
			if (contents[i].num != 0)
			{
				total += contents[i].num;
				contents[j] = contents[i];
				j++;
			}
			i++;
		}
		while (j < i)
		{
			contents[j] = RackEntry.NONE;
			j++;
		}
	}

	bool empty () @property const
	{
		return total == 0;
	}

	string toString () const
	{
		string res = "Rack:";
		foreach (c; contents)
		{
			if (c == RackEntry.NONE)
			{
				break;
			}
			res ~= ' ';
			res ~= to !(string) (c.num);
			res ~= (c.letter == LET) ? '?' : (c.letter + 'A');
		}
		if (contents.length == 0)
		{
			res ~= " empty";
		}
		return res;
	}
}

struct TileBag
{
	Rack rack;

	immutable (byte) [] contents;
	
	void fill_rack ()
	{
		while ((contents.length > 0) && (rack.total < Rack.MAX_SIZE))
		{
			rack.add (contents[0]);
			contents = contents[1..$];
		}
	}

	bool empty () @property const
	{
		return (contents.length == 0) && rack.empty;
	}

	this (const string data)
	{
		byte [] temp;
		foreach (c; data)
		{
			if (c == '?')
			{
				temp ~= LET;
			}
			else
			{
				enforce ('A' <= c && c <= 'Z');
				temp ~= to !(byte) (c - 'A');
			}
		}
		contents = temp.idup;

		fill_rack ();
	}
	
	string toString () const
	{
		string res = rack.toString () ~ "\nFuture tiles: ";
		foreach (c; contents)
		{
			res ~= (c == LET) ? '?' : (c + 'A');
		}
		return res;
	}
}

struct Problem
{
	string name;
	string contents;
	
	this (const string new_name, const string new_contents)
	{
		name = new_name;
		contents = new_contents;
	}
}

class ProblemSet
{
	Problem [] problem;

	this (const char [] [] line_list)
	{
		foreach (line; line_list)
		{
			auto temp = line.split ();
			problem ~= Problem (to !(string) (temp[0]),
			    to !(string) (temp[1]));
		}
		debug {writeln ("ProblemSet: loaded ", problem.length,
		    " problems");}
	}
}

struct GameState
{
	Board board;
	TileBag tiles;
	GameMove recent_move;

	this (Problem new_problem)
	{
		tiles = TileBag (new_problem.contents);
	}

	string toString ()
	{
		string res = board.toString () ~ tiles.toString () ~ '\n';
		string [] moves;
		for (GameMove cur_move = recent_move; cur_move !is null;
		    cur_move = cur_move.prev_move)
		{
			moves ~= to !(string) (cur_move);
		}
		reverse (moves);
		res ~= join (moves, ",\n");
		return res;
	}
}

class GameMove
{
	BoardCell [] word;
	byte row;
	byte col;
	bool is_flipped;
	int score;
	GameMove prev_move;

//	this () @disable;

	this (ref GameState cur, int new_row, int new_col, int add_score)
	{
		row = to !(byte) (new_row);
		col = to !(byte) (new_col);
		while (col > 0 && cur.board[row][col - 1] != BoardCell.NONE)
		{
			col--;
		}
		foreach (cur_col; col..new_col + 1)
		{
			word ~= cur.board[row][cur_col];
		}
//		writeln (col, ' ', new_col, ' ', word, ' ', add_score);
		is_flipped = cur.board.is_flipped;
		score = add_score;
		prev_move = cur.recent_move;
	}

	static string row_str (const int val)
	{
		return to !(string) (val + 1);
	}

	static string col_str (const int val)
	{
		return "" ~ to !(char) (val + 'A');
	}

	override string toString () const
	{
		string coord;
		if (is_flipped)
		{
			coord ~= col_str (row);
			coord ~= row_str (col);
		}
		else
		{
			coord ~= row_str (row);
			coord ~= col_str (col);
		}
 
		auto sink = appender !(string) ();
		formattedWrite (sink, "%3s %(%s%) %4s", coord, word, score);
		return sink.data;
	}
}

class Game
{
	immutable static int FLAG_CONN = 1;
	immutable static int FLAG_ACT = 2;
	immutable static int STORE_BESTS = 200;

	Problem problem;
	Trie trie;
	Scoring scoring;
	GameState [] [] gs;
	GameState best;

	void consider (ref GameState cur, int row, int col,
	    int vert, int score, int mult, int flags)
	{
/*
		writeln ("got ", row, ' ', col, ' ',
		    vert, ' ', score, ' ', mult, ' ',
		    cur.tiles.rack);
*/
		int num = 0;
		foreach (cur_row; 0..Board.SIZE)
		{
			foreach (cur_col; 0..Board.SIZE)
			{
				num += (cur.board[cur_row][cur_col] !=
				    BoardCell.NONE);
			}
		}
		int add_score = vert + score * mult +
		    scoring.bingo * (flags >= Rack.MAX_SIZE * FLAG_ACT);
		if (gs[num].length == STORE_BESTS &&
		    gs[num][$ - 1].board.score >= cur.board.score + add_score)
		{
			return;
		}
		
        	auto next = cur;
		foreach (cur_row; 0..Board.SIZE)
		{
			foreach (cur_col; 0..Board.SIZE)
			{
				next.board[cur_row][cur_col].active = false;
			}
		}
        	next.board.score += add_score;
        	next.tiles.rack.normalize ();
        	next.tiles.fill_rack ();
        	next.recent_move = new GameMove (cur, row, col, add_score);
/*
		writeln (next);
*/
        	int i = 0;
        	while (i < gs[num].length &&
        	       gs[num][i].board.score >= next.board.score)
        	{
        		i++;
        	}
        	gs[num] = gs[num][0..i] ~ next ~
        	    gs[num][i..$ - (gs[num].length == STORE_BESTS)];

        	if (best.board.score < next.board.score)
        	{
        		best = next;
        	}
	}

	int check_vertical (ref GameState cur,
	    const int row_init, const int col)
	{
		if (!cur.board[row_init][col].active)
		{
			return 0;
		}
		int row = row_init;
		while (row > 0 && cur.board[row - 1][col] != BoardCell.NONE)
		{
			row--;
		}
		if (row == row_init)
		{
			if (row == Board.SIZE - 1 ||
			    cur.board[row + 1][col] == BoardCell.NONE)
			{
				return 0;
			}
		}
		int score = 0;
		int mult = 1;
		int v = Trie.ROOT;
		do
		{
			v = trie.next (v, cur.board[row][col].letter);
			scoring.account (score, mult,
			    cur.board[row][col], row, col);
			if (v == NA)
			{
				return NA;
			}
			row++;
		}
		while (row < Board.SIZE &&
		    cur.board[row][col] != BoardCell.NONE);
		if (!trie.contents[v].word)
		{
			return NA;
		}
		return score * mult;
	}

	void step_recur (ref GameState cur, int row, int col,
	    int vert, int score, int mult, int vt, int flags)
	{
		assert (cur.board[row][col] != BoardCell.NONE);
		vt = trie.next (vt, cur.board[row][col]);
		if (vt == NA)
		{
			return;
		}
		int add = check_vertical (cur, row, col);
		if (add == NA)
		{
			return;
		}
		if (add > 0)
		{
			flags |= FLAG_CONN;
		}
		vert += add;
		scoring.account (score, mult, cur.board[row][col], row, col);
		if (row == Board.SIZE / 2 && col == Board.SIZE / 2)
		{
			flags |= FLAG_CONN;
		}
		if (col + 1 == Board.SIZE ||
		    cur.board[row][col + 1] == BoardCell.NONE)
		{
			if ((flags & FLAG_CONN) &&
			    flags >= FLAG_ACT * (1 + cur.board.is_flipped) &&
			    trie.contents[vt].word)
			{
				consider (cur, row, col,
				    vert, score, mult, flags);
			}
		}
		if (col + 1 < Board.SIZE)
		{
			move_recur (cur, row, col + 1,
			    vert, score, mult, vt, flags);
		}
	}

	void move_recur (ref GameState cur, int row, int col,
	    int vert, int score, int mult, int vt, int flags)
	{
/*
		debug {writeln ("move_recur in  ",
		    row, ' ', col, ' ', flags, ' ', score);}
		scope (exit)
		{
			debug {writeln ("move_recur out ",
			    row, ' ', col, ' ', flags, ' ', score);}
		}
*/
		if (cur.board[row][col] != BoardCell.NONE)
		{
			step_recur (cur, row, col,
			    vert, score, mult, vt, flags | FLAG_CONN);
			return;
		}
		foreach (ref c; cur.tiles.rack.contents)
		{
			if (c == RackEntry.NONE)
			{
				break;
			}
			if (c.num != 0)
			{
				c -= 1 << LET_BITS;
				scope (exit)
				{
					c += 1 << LET_BITS;
				}
				if (c.letter != LET)
				{
					cur.board[row][col] = c.letter |
					    (1 << BoardCell.ACTIVE_SHIFT);
					step_recur (cur, row, col,
					    vert, score, mult, vt,
					    flags + FLAG_ACT);
					continue;
				}
				foreach (ubyte letter; 0..LET)
				{
					cur.board[row][col] = letter |
					    (1 << BoardCell.WILDCARD_SHIFT) |
					    (1 << BoardCell.ACTIVE_SHIFT);
					step_recur (cur, row, col,
					    vert, score, mult, vt,
					    flags + FLAG_ACT);
				}
			}
		}
		cur.board[row][col] = BoardCell.NONE;
	}
	
	void move_horizontal (ref GameState cur)
	{
		foreach (row; 0..Board.SIZE)
		{
			foreach (col; 0..Board.SIZE)
			{
				if (col > 0 &&
				    cur.board[row][col - 1] != BoardCell.NONE)
				{
					continue;
				}

				move_recur (cur, row, col, 0, 0, 1,
				    Trie.ROOT, 0);
			}
		}
	}

	void move_start (ref GameState cur)
	{
//		writeln (cur);
		move_horizontal (cur);
		if (cur.board[Board.SIZE / 2][Board.SIZE / 2] !=
		    BoardCell.NONE)
		{
			cur.board.flip ();
			move_horizontal (cur);
			cur.board.flip ();
		}
	}

	void play ()
	{
		gs = new GameState [] [problem.contents.length + 1];
		auto initial_state = GameState (problem);
		gs[0] ~= initial_state;
		foreach (k, gs_line; gs)
		{
//			writeln ("filled ", k, " tiles");
			foreach (gs_element; gs_line)
			{
				move_start (gs_element);
			}
		}
	}

	this (Problem new_problem, Trie new_trie, Scoring new_scoring)
	{
		problem = new_problem;
		trie = new_trie;
		scoring = new_scoring;
	}
	
	override string toString ()
	{
		string [] moves;
		for (GameMove cur_move = best.recent_move; cur_move !is null;
		    cur_move = cur_move.prev_move)
		{
			moves ~= to !(string) (cur_move);
		}
		reverse (moves);
		return join (moves, ",\n");
	}
}

void main ()
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_159);
	auto s = new Scoring ();
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
	GC.collect ();
	foreach (i; 0..26)
	{
		auto g = new Game (ps.problem[i], t, s);
		g.play ();
		writeln ("" ~ to !(char) (i + 'A') ~ ':');
		writeln (g);
		writeln (';');
		stderr.writeln ("" ~ to !(char) (i + 'A') ~ ": " ~
			to !(string) (g.best.board.score));
	}
/*
	while (true)
	{
	}
*/
}
