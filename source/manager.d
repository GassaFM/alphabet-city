module manager;

import std.algorithm;
import std.conv;
import std.exception;
import std.range;
import std.stdio;
import std.string;

import board;
import game_complex;
import game_move;
import game_state;
import general;
import problem;

class Manager
{
	ProblemSet problem_set;
	GameState [string] best;

	static string file_name (const char [] problem_name) pure
	{
		return "data/best/" ~ problem_name ~ ".txt";
	}

	void load_file (const char [] problem_name)
	{
		try
		{
			auto f = File (file_name (problem_name), "rt");
			string s;
			s = f.readln ().strip (); // X: score (other info)...
			enforce (!s.empty);
			best[problem_name] = GameState.read (f);
		}
		catch (Exception e)
		{
			best[problem_name] = GameState.init;
		}
	}

	void save_file (const char [] problem_name)
	{
		auto f = File (file_name (problem_name), "wt");
		best[problem_name].write (f, problem_name.toUpper ~ ":");
	}

	void close ()
	{
		foreach (problem; problem_set.problem)
		{
			save_file (problem.short_name);
		}
	}

	void consider (ref GameState cur, const char [] short_name)
	{
		if (best[short_name].board.score < cur.board.score)
		{
			stderr.writeln (toUpper (short_name), ": ",
			    "new maximum found: ",
			    best[short_name].board.score, " up to ",
			    cur.board.score, "!");
			stderr.flush ();
			best[short_name] = cur;
			save_file (short_name);
		}
	}

	void output (ref GameState cur, const char [] short_name)
	{
		writeln (toUpper (short_name), ':');
		string [] moves;
		for (GameMove cur_move = cur.closest_move; cur_move !is null;
		    cur_move = cur_move.chained_move)
		{
			moves ~= to !(string) (cur_move);
		}
		reverse (moves);
		writeln (join (moves, ",\n"));
		writeln (';');
	}

	void process_log (const char [] file_name,
	    void delegate (ref GameState, const char []) dg)
	{
		File f;
		try
		{
			f = File (to !(string) (file_name), "rt");
		}
		catch (Exception e)
		{
			return;
		}
		stderr.writeln ("Processing log: ", file_name);
		stderr.flush ();
		while (true)
		{
			string s;
			s = f.readln ().strip (); // X: score (other info)...
			if (f.eof ())
			{
				break;
			}
			if (!(s.length >= 2 &&
			    'A' <= s[0] && s[0] <= 'Z' && s[1] == ':'))
			{
				continue;
			}
			string short_name = toLower (s[0..1]);
			auto cur = GameState.read (f);
			dg (cur, short_name);
		}
	}

	void read_log (const char [] file_name)
	{
		process_log (file_name, &consider);
	}

	void extract_log (const char [] file_name)
	{
		process_log (file_name, &output);
	}

	this (ProblemSet new_problem_set)
	{
		problem_set = new_problem_set;
		foreach (problem; problem_set.problem)
		{
			load_file (problem.short_name);
		}
	}

	~this ()
	{
		assert (true);
	}
}
