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
import manager;
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
	version (manager)
	{
		auto m = new Manager (ps);
		m.read_log ("log.txt");
		m.read_log ("log2.txt");
		m.read_log ("log3.txt");
		m.read_log ("log4.txt");
		m.read_log ("log5.txt");
		m.read_log ("log6.txt");
		m.read_log ("log7.txt");
		m.read_log ("log8.txt");
		m.read_log ("log9.txt");
//		m.read_log ("log10.txt");
		m.read_log ("log11.txt");
		m.read_log ("log12.txt");
		m.close ();
		return;
	}

	immutable int UPPER_LIMIT = TOTAL_TILES;
//	immutable int LOWER_LIMIT = UPPER_LIMIT - Rack.MAX_SIZE;
//	immutable int LOWER_LIMIT = UPPER_LIMIT - 11;
//	immutable int LOWER_LIMIT = TOTAL_TILES >> 1;
	immutable int LOWER_LIMIT = 0;

/*
	foreach (p; ps.problem)
	{
		foreach (ref goal; goals)
		{
			goal.stored_score_rating = goal.calc_score_rating (s);
			goal.stored_best_times = goal.calc_best_times
			    (TileBag (p));
			goal.stored_times = goal.calc_times
			    (TileBag (p),
			    goal.stored_best_times.x,
			    goal.stored_best_times.y);
		}
		sort !((a, b) => a.holes_rating < b.holes_rating,
		    SwapStrategy.stable) (goals);
		sort !((a, b) => a.score_rating > b.score_rating,
		    SwapStrategy.stable) (goals);
		writeln (p);
//		writefln ("%(%s\n%)", goals.filter
//		    !(a => a.get_times.length > 1));
		writefln ("%(%s\n%)", goals.filter
		    !(a => true));
//		writefln ("%(%s\n%)", goals.filter
//		    !(a => a.get_times.length == Rack.MAX_SIZE &&
//		    a.get_times[0] >= UPPER_LIMIT - 1 &&
//		    a.get_times[$ - 1] >= LOWER_LIMIT));
		stdout.flush ();
	}
*/

	GC.collect ();
	bool started_output = false;

	foreach (i; 0..1)
	{
/*
		if (i != 's' - 'a')
		{
			continue;
		}
*/
		auto p = ps.problem[i];
		foreach (ref goal; goals)
		{
			goal.stored_score_rating = goal.calc_score_rating (s);
/*
			goal.stored_best_times = goal.calc_best_times
			    (TileBag (p));
*/
			goal.stored_best_times = goal.calc_best_times
			    (TileBag (p), LOWER_LIMIT, UPPER_LIMIT);
			goal.stored_times = goal.calc_times
			    (TileBag (p),
			    goal.stored_best_times.x,
			    goal.stored_best_times.y);
		}
		sort !((a, b) => a.holes_rating < b.holes_rating,
		    SwapStrategy.stable) (goals);
		sort !((a, b) => a.get_best_times.x < b.get_best_times.x,
		    SwapStrategy.stable) (goals);
		sort !((a, b) => a.get_best_times.y - a.get_best_times.x <
		    b.get_best_times.y - b.get_best_times.x,
		    SwapStrategy.stable) (goals);
		sort !((a, b) => a.score_rating > b.score_rating,
		    SwapStrategy.stable) (goals);

                int k = 0;
		foreach (goal_original; goals.filter
		    !(a => a.get_best_times.x != NA &&
		    a.holes_rating <= 30 &&
//		    a.holes_rating <= 50 &&
//		    a.get_times.length > 1 &&
		    a.get_times.length == Rack.MAX_SIZE &&
//		    a.get_times[2] >= a.get_times[0] - 5 &&
		    a.score_rating >= 1000).take (1))
/*
		    a.get_times[$ - 3] >= a.get_times[0] - 12 &&
		    a.get_times[$ - 1] >= a.get_times[0] - 20
*/
//		foreach (goal; goals.filter
//		    !(a => a.get_times.length >= 5 &&
//		      a.holes_rating <= 32).take (4))
//		foreach (gte; filter
//		    !(a => a.s.length == 7 &&
//		    a.s[0] >= UPPER_LIMIT - 1 &&
//		    a.s[6] >= UPPER_LIMIT - 7) (gt))
		{
			auto goal = new Goal (goal_original);
			k++;
			if (k <= 0)
			{
				continue;
			}
			int lo = goal.get_best_times.x;
			int hi = goal.get_best_times.y;
			auto p_prepare = Problem (p.name,
			    p.contents[0..hi - 1],
			    p.contents[hi - 1..$]);
//			    p.contents[hi - 1..hi]);
			auto p_main = Problem (p.name,
			    p.contents[0..$]);
//			    p.contents[0..hi]);

			foreach (bias; 0..3)
			{
				scope (exit)
				{
					GC.collect ();
				}
				auto game = new Game (p, t, s);
//				auto game = new Game (p_prepare, t, s);
				game.goals = [goal];
				goal.letter_bonus = 100;
				stderr.writeln (p.name, ' ', bias, ' ', goal);
				stderr.flush ();

				void log_progress ()
				{
					stderr.writeln (p.name, ' ',
					    game.best.board.score, " (",
					    game.best.board.value, ')');
					stderr.flush ();
					if (game.best.board.score < 2000 ||
					    game.best.tiles.contents.length <
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
					writeln (game);
					stdout.flush ();
				}

				goal.stage = Goal.Stage.COMBINED;
				game.bias = bias;
				game.play (100, 0, Game.Keep.False);
//				game.play (500, 0, Game.Keep.True);
				log_progress ();
				if (game.best.board.score < 1600)
				{
					continue;
				}

				game.moves_guide = GameMove.invert
				    (game.best.closest_move);
/*
				writeln ("1:");
				for (GameMove cur_move = game.moves_guide;
				    cur_move !is null;
				    cur_move = cur_move.chained_move)
				{
					writeln (cur_move);
				}
				stdout.flush ();
*/
				game.moves_guide = game.reduce_move_history
				    (game.moves_guide);
/*
				writeln ("2:");
				for (GameMove cur_move = game.moves_guide;
				    cur_move !is null;
				    cur_move = cur_move.chained_move)
				{
					writeln (cur_move);
				}
				stdout.flush ();
*/

				auto game_copy = new Game (p, t, s);
				game = game_copy;
				game.goals = [goal];
				goal.letter_bonus = 0;
				game.bias = 0;
				game.play (100, 0, Game.Keep.False);
				log_progress ();

/*
				game.resume (1000, 0, 0, Game.Keep.True, true);
				log_progress ();

				game.goals = [];
				game.bias = -bias;
				game.resume (500, 0, 0, Game.Keep.False, true);
				log_progress ();

				auto game2 = new Game (p, t, s);
				game2.moves_guide = game.moves_guide;
				game2.bias = -bias;
				game = game2;
				game.play (500, 0, Game.Keep.False);
				log_progress ();

				auto game3 = new Game (p, t, s);
				game3.moves_guide = game.moves_guide;
				game = game3;
				game.play (500, 0, Game.Keep.False);
				log_progress ();
*/

/*
				game.bias = +bias;
				game.play (100, 0, Game.Keep.True);
				log_progress ();

				game.bias = -bias;
				game.resume (300, 0, 0, Game.Keep.True);
				log_progress ();

				game.bias = +bias;
				game.resume (900, 0, 0, Game.Keep.True);
				log_progress ();

				game.bias = -bias;
				game.resume (2700, 0, 0, Game.Keep.True);
				log_progress ();
//				game.problem = p_main;
//				goal.stage = Goal.Stage.MAIN;
//				game.bias = 0;
//				game.resume (700, 0, hi, Game.Keep.True, true);
				game.goals = [];
				game.resume (8100, 0, hi, Game.Keep.False);
				log_progress ();
*/

/*
				game.problem = p;
				goal.stage = Goal.Stage.DONE;
				game.resume (250, 0, Game.Keep.False);
				log_progress ();
*/
			}
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
		auto game = new Game (ps.problem[i], t, s);
		game.play (10, 0);
		if (started_output)
		{
			writeln (';');
		}
		started_output = true;
		writeln (ps.problem[i].name);
		writeln (g);
		stdout.flush ();
		stderr.writeln ("" ~ to !(char) (i + 'A') ~ ": " ~
		    to !(string) (game.best.board.score) ~ " " ~
		    to !(string) (game.best.board.value));
		GC.collect ();
	}
*/
}
