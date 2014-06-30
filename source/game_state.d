module game_state;

import std.algorithm;
import std.conv;
import std.range;
import std.string;
import std.stdio;

import board;
import game_move;
import problem;
import tile_bag;

struct GameState
{
	Board board;
	TileBag tiles;
	GameMove closest_move;

	ulong get_board_hash () const
	{
		return board.contents_hash[0];
	}

	void xor_active ()
	{
		assert (closest_move !is null);
		closest_move.xor_active (board);
	}

	static GameState read (ref File f)
	{
		GameState res;
		bool to_end = false;
		while (!to_end)
		{
			auto s = f.readln ().strip ();
			if (s.empty)
			{
				break;
			}
			if (s[$ - 1] == ',')
			{
				s.length--;
			}
			else
			{
				to_end = true;
			}
			res.closest_move = new GameMove (s, res.closest_move);
			res.board.score += res.closest_move.score;
		}
		res.board.value = res.board.score;
		return res;
	}

	void write (ref File f, const char [] problem_name)
	{
		f.writefln ("%s %s (%s)", problem_name,
		    board.score, board.value);
		string [] moves;
		for (GameMove cur_move = closest_move; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			moves ~= to !(string) (cur_move);
		}
		reverse (moves);
		f.writefln ("%-(%s,\n%)", moves);
	}

	this (Problem new_problem)
	{
		tiles = TileBag (new_problem);
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
		for (GameMove cur_move = closest_move; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			moves ~= to !(string) (cur_move);
		}
		reverse (moves);
		res ~= join (moves, ",\n");
		return res;
	}
}
