module manager;

import std.conv;
import std.exception;
import std.range;
import std.stdio;
import std.string;

import board;
import game;
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

	void read_log (const char [] file_name)
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
			consider (cur, short_name);
		}
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
