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

	byte contents = LET;

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
		if (letter == LET)
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
		return res;
	}
}

class Scoring
{
	enum BONUS: byte {NO, DW, TW, DL, TL};
	immutable static string [BONUS.max - BONUS.min + 1] BONUS_NAME =
	    ["--", "DW", "TW", "DL", "TL"];

	BONUS [Board.SIZE] [Board.SIZE] board_bonus;
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
				for (auto b = BONUS.min; b <= BONUS.max; b++)
				{
					if (word == BONUS_NAME[b])
					{
						board_bonus[i][j] =
						    to !(BONUS) (b);
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
	ubyte contents;

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
		foreach (i, ref v; contents)
		{
			if (v == 0)
			{
				v = letter;
			}
			if (v.letter == letter)
			{
				v.inc ();
				break;
			}
		}
		total++;
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
			if (c == 0)
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

	this (Problem new_problem)
	{
		tiles = TileBag (new_problem.contents);
	}

	string toString () const
	{
		return board.toString () ~ tiles.toString ();
	}
}

struct GameMove
{
	BoardCell [] word;
	byte row;
	byte col;
	bool is_flipped;
	int score;

	static string row_str (const int val)
	{
		return to !(string) (val + 1);
	}

	static string col_str (const int val)
	{
		return "" ~ to !(char) (val + 'A');
	}

	string toString () const
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

		auto sink = Appender !(string) ();
		formattedWrite (sink, "%3s %15s %4s", coord, word, score);
		return sink.data;
	}
}

class Game
{
	Problem problem;
	Trie trie;
	Scoring scoring;
	
	void move_start (const ref GameState cur)
	{
		foreach (row; 0..Board.SIZE)
		{
			foreach (col; 0..Board.SIZE)
			{
				if (col > 0 && cur.board[row][col - 1] != LET)
				{
					continue;
				}
			}
		}
	}

	void play ()
	{
		auto game_state = GameState (problem);
		debug {writeln (game_state);}
		move_start (game_state);
	}

	this (Problem new_problem, Trie new_trie, Scoring new_scoring)
	{
		problem = new_problem;
		trie = new_trie;
		scoring = new_scoring;
	}
}

void main ()
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_159);
	auto s = new Scoring ();
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
	GC.collect ();
	auto g = new Game (ps.problem[0], t, s);
	g.play ();
	while (true)
	{
	}
}
