module main;

import core.memory;
import std.algorithm;
import std.conv;
import std.range;
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
	global_scoring = s;
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
	auto goals = GoalBuilder.build_goals
	    (read_all_lines ("data/goals.txt"));

	immutable int UPPER_LIMIT = TOTAL_TILES;
//	immutable int LOWER_LIMIT = UPPER_LIMIT - Rack.MAX_SIZE;
//	immutable int LOWER_LIMIT = UPPER_LIMIT - 11;
	immutable int LOWER_LIMIT = TOTAL_TILES >> 1;

/*
	foreach (p; ps.problem)
	{
		foreach (ref goal; goals)
		{
			goal.stored_times = goal.calc_times
			    (TileBag (p.contents), LOWER_LIMIT, UPPER_LIMIT);
		}
		sort !((a, b) => a.holes_rating < b.holes_rating,
		    SwapStrategy.stable) (goals);
		writeln (p);
//		writefln ("%(%s\n%)", goals.filter
//		    !(a => a.get_times.length > 1));
		writefln ("%(%s\n%)", goals.filter
		    !(a => a.get_times.length == 7));
//		writefln ("%(%s\n%)", goals.filter
//		    !(a => a.get_times.length == Rack.MAX_SIZE &&
//		    a.get_times[0] >= UPPER_LIMIT - 1 &&
//		    a.get_times[$ - 1] >= LOWER_LIMIT));
		stdout.flush ();
	}
*/
	GC.collect ();
	bool started_output = false;

	foreach_reverse (i; 0..LET)
	{
		auto p = ps.problem[i];
		foreach (ref goal; goals)
		{
			goal.stored_times = goal.calc_times
			    (TileBag (p.contents), LOWER_LIMIT, UPPER_LIMIT);
			goal.stored_score_rating = goal.calc_score_rating (s);
			goal.stored_best_times = goal.calc_best_times
			    (TileBag (p.contents));
		}
		sort !((a, b) => a.holes_rating < b.holes_rating,
		    SwapStrategy.stable) (goals);
		sort !((a, b) => a.get_best_times.y - a.get_best_times.x <
		    b.get_best_times.y - b.get_best_times.x,
		    SwapStrategy.stable) (goals);
		sort !((a, b) => a.score_rating > b.score_rating,
		    SwapStrategy.stable) (goals);
/*
		sort !((a, b) => a.get_best_times.x < b.get_best_times.x,
		    SwapStrategy.stable) (goals);
*/

		foreach (goal; goals.filter
		    !(a => a.get_best_times.x != NA && a.score_rating >= 900 &&
		      a.get_best_times.y - a.get_best_times.x <= 15).take (12))
//		foreach (goal; goals.filter
//		    !(a => a.get_times.length >= 5 &&
//		      a.holes_rating <= 32).take (4))
//		foreach (gte; filter
//		    !(a => a.s.length == 7 &&
//		    a.s[0] >= UPPER_LIMIT - 1 &&
//		    a.s[6] >= UPPER_LIMIT - 7) (gt))
		{
			auto p_prepare = Problem (p.name,
			    p.contents[0..goal.get_best_times.x]);
			auto g = new Game (p_prepare, t, s);
			g.goals = [goal];
			stderr.writeln (p.name, ' ', goal);
			stderr.flush ();

			void log_progress ()
			{
				stderr.writeln (p.name, ' ',
				    g.best.board.score, " (",
				    g.best.board.value, ')');
				stderr.flush ();
				if (g.best.board.score < 1400 ||
				    g.best.tiles.contents.length <
				    TOTAL_TILES)
				{
					return;
				}
				if (started_output)
				{
					writeln (';');
				}
				started_output = true;
				writeln (p.name);
				writeln (g);
				stdout.flush ();
			}

			goal.stage = Goal.Stage.PREPARE;
			goal.bias = 3;
			g.play (500, 0, Game.Keep.True);
			log_progress ();

			auto p_main = Problem (p.name,
			    p.contents[0..goal.get_best_times.y]);
			g.problem = p_main;
			goal.stage = Goal.Stage.MAIN;
			g.resume (1600, 0, Game.Keep.True);
			log_progress ();

			g.problem = p;
			goal.stage = Goal.Stage.DONE;
			g.resume (1200, 0, Game.Keep.False);
			log_progress ();

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
