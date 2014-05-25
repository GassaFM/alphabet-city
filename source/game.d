module game;

import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.stdio;
import std.string;

import board;
import general;
import problem;
import scoring;
import tilebag;
import trie;

struct GameState
{
	Board board;
	TileBag tiles;
	GameMove recent_move;

	this (Problem new_problem)
	{
		tiles = TileBag (new_problem.contents);
		board.normalize ();
	}

	bool opEquals (const ref GameState other) const
	{
		return board == other.board;
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
		while (col > 0 && !cur.board[row][col - 1].empty)
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

	Problem problem;
	Trie trie;
	Scoring scoring;
	GameState [] [] gs;
	int [] [] gsp;
	GameState best;
	int bests_num;
	int depth;

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
				num += !cur.board[cur_row][cur_col].empty;
			}
		}
		int add_score = vert + score * mult +
		    scoring.bingo * (flags >= Rack.MAX_SIZE * FLAG_ACT);
		if (depth == 0 && gsp[num].length == bests_num &&
		    gs[num][gsp[num][$ - 1]].board.score >=
		    cur.board.score + add_score)
		{
			return;
		}
		
		auto next = cur;
		next.board.normalize ();
		next.board.score += add_score;
		next.tiles.rack.normalize ();
		next.tiles.fill_rack ();
		next.recent_move = new GameMove (cur, row, col, add_score);
//		debug {writeln (next);}

		if (depth > 0)
		{
			depth--;
			move_start (next);
			depth++;
		}

		if (gsp[num].length == bests_num &&
		    gs[num][gsp[num][$ - 1]].board.score >= next.board.score)
		{
			return;
		}

		int i = 0;
		while (i < gsp[num].length &&
		    gs[num][gsp[num][i]].board.score >= next.board.score)
		{
			if (gs[num][gsp[num][i]].board.contents_hash ==
			    next.board.contents_hash)
			{
				return;
			}
/*
			if (gsp[num].length >= (bests_num - 5) &&
			    gs[num][gsp[num][i]].board.score ==
			    next.board.score)
			{
				return;
			}
*/
			i++;
		}

		scope (exit)
		{
			if (best.board.score < next.board.score)
			{
				best = next;
			}
		}

		int j = i;
		while (j < gsp[num].length)
		{
			int d = gsp[num][j];
			if (gs[num][d].board.contents_hash ==
			    next.board.contents_hash)
			{
				gs[num][d] = next;
				foreach_reverse (k; i..j)
				{
					gsp[num][k + 1] = gsp[num][k];
				}
				gsp[num][i] = d;
				return;
			}
			j++;
		}

		if (gsp[num].length < bests_num)
		{
			int d = gsp[num].length;
			gs[num].assumeSafeAppend ();
			gs[num] ~= next;
			gsp[num].assumeSafeAppend ();
			gsp[num] ~= NA;
			foreach_reverse (k; i..d)
			{
				gsp[num][k + 1] = gsp[num][k];
			}
			gsp[num][i] = d;
		}
		else
		{
			int d = gsp[num][$ - 1];
			gs[num][d] = next;
			foreach_reverse (k; i..gsp[num].length - 1)
			{
				gsp[num][k + 1] = gsp[num][k];
			}
			gsp[num][i] = d;
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
		while (row > 0 && !cur.board[row - 1][col].empty)
		{
			row--;
		}
		if (row == row_init)
		{
			if (row == Board.SIZE - 1 ||
			    cur.board[row + 1][col].empty)
			{
				return 0;
			}
		}
		int score = 0;
		int mult = 1;
		int v = Trie.ROOT;
		do
		{
			v = trie.contents[v].next (cur.board[row][col].letter);
			scoring.account (score, mult,
			    cur.board[row][col], row, col);
			if (v == NA)
			{
				return NA;
			}
			row++;
		}
		while (row < Board.SIZE && !cur.board[row][col].empty);
		if (!trie.contents[v].word)
		{
			return NA;
		}
		return score * mult;
	}

	void step_recur (ref GameState cur, int row, int col,
	    int vert, int score, int mult, int vt, int flags)
	{
		assert (!cur.board[row][col].empty);
		vt = trie.contents[vt].next (cur.board[row][col]);
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
		if (row == Board.CENTER && col == Board.CENTER)
		{
			flags |= FLAG_CONN;
		}
		if (col + 1 == Board.SIZE || cur.board[row][col + 1].empty)
		{
			if (trie.contents[vt].word &&
			    (flags & FLAG_CONN) &&
//			    (flags >= FLAG_ACT * (1 + cur.board.is_flipped)))
//			    (flags >= FLAG_ACT))
			    (flags >= FLAG_ACT *
			    (1 + (cur.board.is_flipped && (vert > 0)))))
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
		if (!cur.board[row][col].empty)
		{
			step_recur (cur, row, col,
			    vert, score, mult, vt, flags | FLAG_CONN);
			return;
		}
		foreach (ref c; cur.tiles.rack.contents)
		{
			if (c.empty)
			{
				break;
			}
			if (c.num != 0)
			{
				c.dec ();
				scope (exit)
				{
					c.inc ();
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
				if (cur.board.can_start_move (row, col,
				    cur.tiles.rack.total))
				{
					move_recur (cur, row, col, 0, 0, 1,
					    Trie.ROOT, 0);
				}
			}
		}
	}

	void move_start (ref GameState cur)
	{
//		writeln (cur);
		move_horizontal (cur);
		if (!cur.board[Board.CENTER][Board.CENTER].empty)
		{
			cur.board.flip ();
			move_horizontal (cur);
			cur.board.flip ();
		}
	}

	void play (int new_bests_num, int new_depth)
	{
		bests_num = new_bests_num;
		depth = new_depth;

		gs = new GameState [] [problem.contents.length + 1];
		gsp = new int [] [problem.contents.length + 1];
		foreach (k, gsp_line; gsp)
		{
			gs[k].reserve (bests_num);
			gsp[k].reserve (bests_num);
		}
		auto initial_state = GameState (problem);
		gs.assumeSafeAppend ();
		gs[0] ~= initial_state;
		gsp.assumeSafeAppend ();
		gsp[0] ~= 0;
		foreach (k, gsp_line; gsp)
		{
			writeln ("filled ", k, " tiles");
			foreach (i, gsp_element; gsp_line)
			{
				if (min (i, gsp_line.length - i) < 10)
				{
					writeln ("at:");
					writeln (gs[k][gsp_element]);
					stdout.flush ();
				}
				move_start (gs[k][gsp_element]);
			}
			gs[k] = null;
			gsp[k] = null;
		}
		gs = null;
		gsp = null;
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
