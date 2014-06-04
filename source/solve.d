module main;

import core.memory;
import std.algorithm;
import std.conv;
import std.range;
import std.stdio;
import std.typecons;

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

void log_progress (Game game)
{
	static bool started_output = false;

	stderr.writeln (game.problem.name, ' ',
	    game.best.board.score, " (",
	    game.best.board.value, ')');
	stderr.flush ();
	if (game.best.board.score < 2300 ||
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
	writeln (game.problem.name);
	writeln (game);
	stdout.flush ();
}

void main ()
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
//	auto t = new Trie (read_all_lines ("data/words8.txt"), 233_691);
	auto s = new Scoring ();
	global_scoring = s;
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
	auto goals = GoalBuilder.build_goals
	    (read_all_lines ("data/goals.txt"));
	auto m = new Manager (ps);
	version (manager)
	{
		m.read_log ("log.txt");
		foreach (c; 2..21)
		{
			m.read_log ("log" ~ to !(string) (c) ~ ".txt");
		}
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

	immutable int MIDDLE = 53;
	foreach (i; 0..LET)
	{
		auto p = ps.problem[i];
		foreach (ref goal; goals)
		{
			goal.stored_score_rating = goal.calc_score_rating (s);
			goal.stored_best_times = goal.calc_best_times
			    (TileBag (p), 0, MIDDLE);
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

		foreach (goal_original; goals.filter
		    !(a => a.get_best_times.x != NA &&
		    a.holes_rating < 50 &&
		    a.get_times.length > 2 &&
//		    a.get_times.length == Rack.MAX_SIZE &&
		    a.get_times[2] >= a.get_times[0] - 5 &&
		    a.get_times[$ - 1] >= a.get_times[0] - 35 &&
		    a.score_rating >= 1000).take (5))
		{
			auto goal = new Goal (goal_original);
			int lo = goal.get_best_times.x;
			int hi = goal.get_best_times.y;
			auto p_first = Problem (p.name,
			    p.contents[0..MIDDLE]);

			foreach (bias; 0..3)
			{
				scope (exit)
				{
					GC.collect ();
				}
				auto game = new Game (p_first, t, s);
				game.goals = [goal];
				goal.letter_bonus = 100;
				stderr.writeln (p.name, ' ', bias, ' ', goal);
				stderr.flush ();

				goal.stage = Goal.Stage.COMBINED;
				game.bias = bias;
				game.play (1000, 0, Game.Keep.True);
				log_progress (game);
				if (game.best.board.score < 1000)
				{
					continue;
				}

				auto goals2 = goals.dup;
				foreach (ref goal2; goals2)
				{
					goal2 = new Goal (goal2);
					goal2.row = Board.SIZE - 1;
				}
				foreach (ref goal2; goals2)
				{
					goal2.stored_best_times =
					    goal2.calc_best_times
					    (TileBag (p),
					    TOTAL_TILES - MIDDLE,
					    TOTAL_TILES);
					goal2.stored_times = goal2.calc_times
					    (TileBag (p),
					    goal2.stored_best_times.x,
					    goal2.stored_best_times.y);
				}
				sort !((a, b) =>
				    a.holes_rating < b.holes_rating,
				    SwapStrategy.stable) (goals2);
				sort !((a, b) =>
				    a.get_best_times.x < b.get_best_times.x,
				    SwapStrategy.stable) (goals2);
				sort !((a, b) =>
				    a.get_best_times.y - a.get_best_times.x <
				    b.get_best_times.y - b.get_best_times.x,
				    SwapStrategy.stable) (goals2);
				sort !((a, b) =>
				    a.score_rating > b.score_rating,
				    SwapStrategy.stable) (goals2);

				foreach (goal2_original; goals2.filter
				    !(a => a.get_best_times.x != NA &&
				    a.holes_rating < 50 &&
				    a.get_times.length > 1 &&
//				    a.get_times.length == Rack.MAX_SIZE &&
				    a.get_times[2] >= a.get_times[0] - 5 &&
				    a.get_times[$ - 1] >=
				    a.get_times[0] - 35 &&
				    a.score_rating +
				    goal.score_rating >= 1800).take (5))
				{
					auto goal2 = new Goal (goal2_original);
					goal.letter_bonus = 200;
					goal2.letter_bonus = 100;
					stderr.writeln (p.name, ' ', goal2);
					stderr.flush ();

					game.goals = [goal, goal2];
					game.problem = p;
					goal2.stage = Goal.Stage.COMBINED;
					game.bias = -bias;
					game.resume (2000, 0,
					    TOTAL_TILES - MIDDLE,
					    Game.Keep.True, true);
					log_progress (game);
					goal.letter_bonus = 100;
				}
			}
		}
	}
	return;

	foreach_reverse (i; 0..LET)
	{
		if (i != 'F' - 'A' && i != 'U' - 'A')
		{
			continue;
		}
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

/*
				goal.stage = Goal.Stage.COMBINED;
				game.bias = bias;
				game.play (500, 0, Game.Keep.False);
//				game.play (500, 0, Game.Keep.True);
				log_progress (game);
				if (game.best.board.score < 1600)
				{
					continue;
				}
*/

				auto temp = m.best["" ~ to !(char) (i + 'a')];
				temp.closest_move = game.restore_moves (temp);
				game.forced_lock_wildcards = true;
				game.moves_guide = GameMove.invert
				    (temp.closest_move);
//				game.moves_guide = GameMove.invert
//				    (game.best.closest_move);
				GameMove [] gm1;
				for (GameMove cur_move = game.moves_guide;
				    cur_move !is null;
				    cur_move = cur_move.chained_move)
				{
					gm1 ~= cur_move;
				}
				stderr.writefln
				    ("complete guide (%s): %(%s, %)",
				    gm1.length, gm1);
				stderr.flush ();
				goal.stage = Goal.Stage.COMBINED;
				auto temp_history = game.reduce_move_history
				    (game.moves_guide);
				game.moves_guide = temp_history[0];
				auto p_freed = temp_history[1];
				stderr.writeln (p_freed.contents.length, ' ',
				    p_freed);
				stderr.flush ();
				GameMove [] gm2;
				for (GameMove cur_move = game.moves_guide;
				    cur_move !is null;
				    cur_move = cur_move.chained_move)
				{
					gm2 ~= cur_move;
				}
				stderr.writefln
				    ("necessary guide (%s): %(%s, %)",
				    gm2.length, gm2);
				stderr.flush ();

/*
				game.bias = 0;
				goal.letter_bonus = 0;
				game.play (1000, 0, Game.Keep.False);
				log_progress (game);
*/

				auto goals2 = goals.dup;
				foreach (ref goal2; goals2)
				{
					goal2 = new Goal (goal2);
					goal2.row = Board.SIZE - 1;
				}
				immutable int LOWER_LIMIT2 = 20; // of ~60
				foreach (ref goal2; goals2)
				{
					goal2.stored_best_times =
					    goal2.calc_best_times
					    (TileBag (p_freed),
					    LOWER_LIMIT2, UPPER_LIMIT);
					goal2.stored_times = goal2.calc_times
					    (TileBag (p_freed),
					    goal2.stored_best_times.x,
					    goal2.stored_best_times.y);
				}
/*
				sort !((a, b) =>
				    a.holes_rating < b.holes_rating,
				    SwapStrategy.stable) (goals2);
				sort !((a, b) =>
				    a.get_best_times.x < b.get_best_times.x,
				    SwapStrategy.stable) (goals2);
				sort !((a, b) =>
				    a.get_best_times.y - a.get_best_times.x <
				    b.get_best_times.y - b.get_best_times.x,
				    SwapStrategy.stable) (goals2);
				sort !((a, b) =>
				    a.score_rating > b.score_rating,
				    SwapStrategy.stable) (goals2);
*/
				sort !((a, b) =>
				    a.get_best_times.x > b.get_best_times.x,
				    SwapStrategy.stable) (goals2);
				sort !((a, b) =>
				    a.get_times.length < b.get_times.length,
				    SwapStrategy.stable) (goals2);

				foreach (goal2_original; goals2.filter
				    !(a => a.get_best_times.x != NA &&
//				    a.holes_rating <= 30 &&
				    a.get_times.length > 1 &&
				    a.get_times.length <= 7 &&
//				    a.get_times.length == Rack.MAX_SIZE &&
//				    a.get_times[2] >= a.get_times[0] - 5 &&
				    a.get_times[$ - 1] >= LOWER_LIMIT2 &&
//				    a.get_times[$ - 1] >=
//				    a.get_times[0] - 15 &&
				    a.score_rating >= 100).take (10))
				{
					auto goal2 = new Goal (goal2_original);
					stderr.writeln (p.name, ' ', goal2);
					stderr.flush ();

/*
					auto p_cur = Problem (p.name,
					    p.contents
					    [0..goal2.get_best_times.y],
					    p.contents
					    [goal2.get_best_times.y..$]);
					auto game2 = new Game (p_cur, t, s);
*/
					auto game2 = new Game (p, t, s);
					game2.goals = [goal2];
					goal2.stage = Goal.Stage.PREPARE;
					game2.moves_guide = game.moves_guide;
					game2.forced_lock_wildcards = true;
					game2.bias = -bias;
					game2.play (2500, 0, Game.Keep.False);
//					game2.play (2500, 0, Game.Keep.True);
					log_progress (game2);

/*
					game2.problem = p;
					goal2.stage = Goal.Stage.COMBINED;
					game2.resume (2500, 0,
					    to !(int) (p_cur.contents.length),
					    Game.Keep.False, false);
					log_progress (game2);
*/
				}

/*
				auto game_copy = new Game (p, t, s);
				game_copy.moves_guide = game.moves_guide;
				game_copy.goals = [goal];
				game_copy.bias = 0;
				goal.letter_bonus = 0;
				game = game_copy;
				game.play (1500, 0, Game.Keep.False);
				log_progress (game);
*/

/*
				game.resume (1000, 0, 0, Game.Keep.True, true);
				log_progress (game);

				game.goals = [];
				game.bias = -bias;
				game.resume (500, 0, 0, Game.Keep.False, true);
				log_progress (game);

				auto game2 = new Game (p, t, s);
				game2.moves_guide = game.moves_guide;
				game2.bias = -bias;
				game2.play (500, 0, Game.Keep.False);
				log_progress (game2);

				auto game3 = new Game (p, t, s);
				game3.moves_guide = game.moves_guide;
				game3.play (500, 0, Game.Keep.False);
				log_progress (game3);
*/

/*
				game.bias = +bias;
				game.play (100, 0, Game.Keep.True);
				log_progress (game);

				game.bias = -bias;
				game.resume (300, 0, 0, Game.Keep.True);
				log_progress (game);

				game.bias = +bias;
				game.resume (900, 0, 0, Game.Keep.True);
				log_progress (game);

				game.bias = -bias;
				game.resume (2700, 0, 0, Game.Keep.True);
				log_progress (game);
//				game.problem = p_main;
//				goal.stage = Goal.Stage.MAIN;
//				game.bias = 0;
//				game.resume (700, 0, hi, Game.Keep.True, true);
				game.goals = [];
				game.resume (8100, 0, hi, Game.Keep.False);
				log_progress (game);
*/

/*
				game.problem = p;
				goal.stage = Goal.Stage.DONE;
				game.resume (250, 0, Game.Keep.False);
				log_progress (game);
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
