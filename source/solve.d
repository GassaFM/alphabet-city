module main;

import core.memory;
import std.algorithm;
import std.conv;
import std.stdio;

import board;
import game;
import fifteen;
import general;
import goal;
import problem;
import scoring;
import tilebag;
import trie;

void main ()
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
//	auto t = new Trie (read_all_lines ("data/words8.txt"), 233_691);
	auto s = new Scoring ();
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
	auto goals = GoalBuilder.build_goals
	    (read_all_lines ("data/goals.txt"));
/*
	foreach (p; ps.problem)
	{
		alias Tuple !(int [], "s", Goal, "g") LocalPair;
		LocalPair [] gt;
		foreach (goal; goals)
		{
			gt ~= LocalPair (goal.calc_times
			    (TileBag (p.contents), LOWER_LIMIT, UPPER_LIMIT),
			    goal);
		}
		sort (gt);
		reverse (gt);
		writeln (p);
		foreach (
		writefln ("%(%s\n%)", filter
		    !(a => a.s.length == 7 &&
		    a.s[0] >= UPPER_LIMIT - 1 &&
		    a.s[6] >= UPPER_LIMIT - 7) (gt));
		stdout.flush ();
	}
*/
	GC.collect ();
	bool started_output = false;

	immutable int UPPER_LIMIT = TOTAL_TILES;
	immutable int LOWER_LIMIT = UPPER_LIMIT - Rack.MAX_SIZE;
	foreach (i; 2..3)
	{
		auto p = ps.problem[i];
		alias Tuple !(int [], "s", Goal, "g") LocalPair;
		LocalPair [] gt;
		foreach (goal; goals)
		{
			gt ~= LocalPair (goal.calc_times
			    (TileBag (p.contents), LOWER_LIMIT, UPPER_LIMIT),
			    goal);
		}
		sort (gt);
		reverse (gt);

		foreach (gte; filter
		    !(a => a.s.length == 7 &&
		    a.s[0] >= UPPER_LIMIT - 1 &&
		    a.s[6] >= UPPER_LIMIT - 7) (gt))
		{
			auto p_reduced = Problem (p.name,
			    p.contents[0..LOWER_LIMIT]);
			auto g = new Game (p_reduced, t, s);
			g.goals = [gte.g];
			g.play (50, 1);
			if (started_output)
			{
				writeln (';');
			}
			started_output = true;
			writeln (gte);
			writeln (p.name);
			writeln (g);
			stdout.flush ();
			stderr.writeln ("" ~ to !(char) (i + 'A') ~ ": " ~
			    to !(string) (g.best.board.score) ~ " " ~
			    to !(string) (g.best.board.value));
			GC.collect ();
		}
	}
/*
	auto goals = GoalBuilder.build_goals (t);
	writefln ("%(%s\n%)", goals);
*/
/*
	auto lws = new LongWordSet (read_all_lines ("data/words.txt"), s, t);
	foreach (lw; lws.contents)
	{
		writeln (lw);
		foreach (p; ps.problem)
		{
			writeln (p);
			foreach (k; 0..3)
			{
				writeln (lw.possible (p, k));
			}
		}
	}
*/
/*
	foreach (i; 2..3)
	{
		auto g = new Game (ps.problem[i], t, s);
		g.play (10, 0);
		if (started_output)
		{
			writeln (';');
		}
		started_output = true;
		writeln (ps.problem[i].name);
		writeln (g);
		stdout.flush ();
		stderr.writeln ("" ~ to !(char) (i + 'A') ~ ": " ~
		    to !(string) (g.best.board.score) ~ " " ~
		    to !(string) (g.best.board.value));
		GC.collect ();
	}
*/
}
