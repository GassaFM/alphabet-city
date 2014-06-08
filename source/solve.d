module main;

import core.memory;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.stdio;
import std.string;
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
	    game.best.tiles.contents.length < TOTAL_TILES)
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

void main (string [] args)
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
//	auto t = new Trie (read_all_lines ("data/words8.txt"), 233_691);
	auto s = new Scoring ();
	global_scoring = s;
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
	auto goals = GoalBuilder.build_fat_goals
	    (read_all_lines ("data/goals.txt"));
	foreach (ref goal; goals)
	{
		goal.stage = Goal.Stage.COMBINED;
		goal.stored_score_rating = goal.calc_score_rating (s);
	}

	auto m = new Manager (ps);
	version (manager)
	{
		m.read_log ("log.txt");
		foreach (c; 1..100)
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

	version (refine)
	{
		foreach (i; 0..LET)
		{
			auto p = ps.problem[i];
			auto game = new Game (p, t, s);
			auto temp = m.best["" ~ to !(char) (i + 'a')];
			temp.closest_move = game.restore_moves (temp);
			game.forced_lock_wildcards = true;
			game.moves_guide = GameMove.invert
			    (temp.closest_move);
			int beam_width = 1000;
			int beam_depth = 0;
			stderr.writeln (p.name, ' ', temp.board.score, ' ',
			    beam_width, ' ', beam_depth);

			GameMove [] gm1;
			for (GameMove cur_move = game.moves_guide;
			    cur_move !is null;
			    cur_move = cur_move.chained_move)
			{
				gm1 ~= cur_move;
			}
			stderr.writefln ("complete guide (%s): %(%s, %)",
			    gm1.length, gm1);
			stderr.flush ();

			auto temp_history = game.reduce_move_history
			    (game.moves_guide);
			game.moves_guide = temp_history[0];
			auto p_freed = temp_history[1];

			GameMove [] gm2;
			for (GameMove cur_move = game.moves_guide;
			    cur_move !is null;
			    cur_move = cur_move.chained_move)
			{
				gm2 ~= cur_move;
			}
			stderr.writefln ("necessary guide (%s): %(%s, %)",
			    gm2.length, gm2);
			stderr.flush ();

			game.play (beam_width, beam_depth, Game.Keep.False);
			log_progress (game);
		}
		return;
	}

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

	immutable int MIDDLE = 50;

	if (args.length > 1)
	{
		args.popFront ();
		auto temp_str = args.front ();
		args.popFront ();
		enforce (temp_str.length == 1 &&
		    'A' <= temp_str[0] && temp_str[0] <= 'Z');
		int i = temp_str[0] - 'A';
		int beam_width = to !(int) (args.front ());
		args.popFront ();
		int beam_depth = 0;
		int bias = to !(int) (args.front ());
		args.popFront ();
		int cur_middle = to !(int) (args.front ());
		args.popFront ();
		auto p = ps.problem[i];
		Goal [] cur_goals;
		foreach (v; args)
		{
			cur_goals ~= new Goal (v);
		}
		enforce (cur_goals.length == 2);

		cur_goals[0].letter_bonus = 200;
		cur_goals[0].stored_best_times = cur_goals[0].calc_best_times
		    (TileBag (p), 0, cur_middle);

		cur_goals[1].letter_bonus = 100;
		cur_goals[1].stored_best_times = cur_goals[1].calc_best_times
		    (TileBag (p), cur_middle, TOTAL_TILES);

		foreach (goal; cur_goals)
		{
			goal.stage = Goal.Stage.COMBINED;
			goal.stored_score_rating = goal.calc_score_rating (s);
			goal.stored_times = goal.calc_times (TileBag (p),
			    goal.stored_best_times.x,
			    goal.stored_best_times.y);
		}

		auto p_first = Problem (p.name, p.contents[0..cur_middle]);

		do
		{
			auto game = new Game (p_first, t, s);
			game.goals = [cur_goals[0]];
			cur_goals[0].row = Board.SIZE - 1;
			game.bias = -bias;
			stderr.writefln ("%s %s %s %(%s\n    %)", p.name,
			    beam_width, beam_depth, game.goals);
			stderr.flush ();
			game.play (beam_width, beam_depth, Game.Keep.True);
			log_progress (game);

			if (game.best.board.score < cur_goals[0].score_rating)
			{
				continue;
			}

			game.problem = p;
			game.goals ~= cur_goals[1];
			cur_goals[1].row = 0;
			game.bias = +bias;
			stderr.writefln ("%s %s %s %(%s\n    %)", p.name,
			    beam_width, beam_depth, game.goals);
			stderr.flush ();
			game.resume (beam_width * 2, beam_depth,
			    cur_middle /* - 10 */, Game.Keep.False,
			    true, false, true);
			log_progress (game);
		}
		while (false);

		do
		{
			auto game = new Game (p_first, t, s);
			game.goals = [cur_goals[0]];
			cur_goals[0].row = 0;
			game.bias = +bias;
			stderr.writefln ("%s %s %s %(%s\n    %)", p.name,
			    beam_width, beam_depth, game.goals);
			stderr.flush ();
			game.play (beam_width, beam_depth, Game.Keep.True);
			log_progress (game);

			if (game.best.board.score < cur_goals[0].score_rating)
			{
				continue;
			}

			game.problem = p;
			game.goals ~= cur_goals[1];
			cur_goals[1].row = Board.SIZE - 1;
			game.bias = -bias;
			stderr.writefln ("%s %s %s %(%s\n    %)", p.name,
			    beam_width, beam_depth, game.goals);
			stderr.flush ();
			game.resume (beam_width * 2, beam_depth,
			    cur_middle /* - 10 */, Game.Keep.False,
			    true, false, true);
			log_progress (game);
		}
		while (false);

		return;
	}

/*
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
		    a.score_rating >= 900).take (5))
		{
			auto goal = new Goal (goal_original);
			goal.stage = Goal.Stage.COMBINED;
			goal.row = 0;
			goal.letter_bonus = 200;
			int lo = goal.get_best_times.x;
			int hi = goal.get_best_times.y;
			auto p_first = Problem (p.name,
			    p.contents[0..MIDDLE]);

			auto goals2 = goals.dup;
			foreach (ref goal2; goals2)
			{
				goal2 = new Goal (goal2);
			}
			foreach (ref goal2; goals2)
			{
				goal2.stored_best_times =
				    goal2.calc_best_times
				    (TileBag (p),
				    MIDDLE, TOTAL_TILES);
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
//			    a.get_times.length == Rack.MAX_SIZE &&
			    a.get_times[2] >= a.get_times[0] - 5 &&
			    a.get_times[$ - 1] >=
			    a.get_times[0] - 35 &&
			    a.score_rating +
			    goal.score_rating >= 1800).take (5))
			{

				auto goal2 = new Goal (goal2_original);
				goal2.stage = Goal.Stage.COMBINED;
				goal2.row = Board.SIZE - 1;
				goal2.letter_bonus = 100;
				stderr.writeln (p.name, "\n", goal, "\n",
				    goal2);
				stderr.flush ();

				{
					auto game = new Game (p, t, s);
					game.goals = [goal, goal2];
					game.play (1600, 0, Game.Keep.False);
					log_progress (game);
				}

				GC.collect ();

				swap (goal.row, goal2.row);
				scope (exit)
				{
					swap (goal.row, goal2.row);
				}
				{
					auto game_inv = new Game (p, t, s);
					game_inv.goals = [goal, goal2];
					game_inv.play (1600, 0,
					    Game.Keep.False);
					log_progress (game_inv);
				}

				GC.collect ();
			}
		}
	}
	return;
*/

	foreach (i; 0..LET)
	{
/*
		if (i != 'Y' - 'A')
		{
			continue;
		}
*/
		auto p = ps.problem[i];
/*
		if (m.best[p.short_name].board.score >= 2713)
		{
			continue;
		}
*/

		auto goals_earliest = goals.dup;
		foreach (ref cur_goal; goals_earliest)
		{
			cur_goal = new Goal (cur_goal);
			cur_goal.stored_best_times =
			    cur_goal.calc_earliest_times
			    (TileBag (p), 0, TOTAL_TILES * 3 / 4);
			cur_goal.stored_times = cur_goal.calc_times
			    (TileBag (p),
			    cur_goal.stored_best_times.x,
			    cur_goal.stored_best_times.y);
		}
		goals_earliest = goals_earliest.filter
		    !(a => a.get_best_times.x != NA &&
//		      a.get_times[0] >= a.get_best_times.y - 14 &&
//		      a.get_times[0] - a.get_times[2] <= 14 &&
		      a.get_times[0] - a.get_times[$ - 1] <= 75).array ();
		sort !((a, b) => a.stored_best_times < b.stored_best_times)
		    (goals_earliest);
		sort !((a, b) => a.score_rating > b.score_rating)
		    (goals_earliest);

		auto goals_latest = goals.dup;
		foreach (ref cur_goal; goals_latest)
		{
			cur_goal = new Goal (cur_goal);
			cur_goal.stored_best_times =
			    cur_goal.calc_latest_times
			    (TileBag (p), TOTAL_TILES * 1 / 4, TOTAL_TILES);
			cur_goal.stored_times = cur_goal.calc_times
			    (TileBag (p),
			    cur_goal.stored_best_times.x,
			    cur_goal.stored_best_times.y);
		}
		goals_latest = goals_latest.filter
		    !(a => a.get_best_times.x != NA &&
//		      a.get_times[0] >= a.get_best_times.y - 14 &&
//		      a.get_times[0] - a.get_times[2] <= 14 &&
		      a.get_times[0] - a.get_times[$ - 1] <= 75).array ();
		sort !((a, b) => a.stored_best_times < b.stored_best_times)
		    (goals_latest);
		sort !((a, b) => a.score_rating < b.score_rating)
		    (goals_latest);

		int SLACK = 0;
		Goal [] [] goal_pairs;
		foreach (goal1; goals_earliest.take (1000))
		{
			foreach_reverse (goal2; goals_latest.take (1000))
			{
				if (goal1.get_best_times.y + SLACK >
				    goal2.get_best_times.x - SLACK)
				{
					continue;
//					break;
				}
				goal_pairs ~= [goal1, goal2];
			}
		}
		stderr.writeln ("Goal pairs for ", p.name, ' ',
		    goal_pairs.length);
		stderr.flush ();
		sort !((a, b) => a[0].score_rating + a[1].score_rating >
		    b[0].score_rating + b[1].score_rating) (goal_pairs);

		GameState [ByteString] lower_cache;
		GameState [ByteString] upper_cache;
		foreach (goal_pair; goal_pairs.take (100))
		{
			stderr.writefln ("%s %(%s\n    %)", p.name, goal_pair);
			stderr.flush ();
			auto cur_goals = goal_pair.dup;
			foreach (ref goal; cur_goals)
			{
				goal = new Goal (goal);
			}

			int beam_width = 250;
			int beam_depth = 0;
			int bias = 3;
//			int cur_middle = goal_pair[0].stored_best_times.y;
			int cur_middle =
			    min (goal_pair[0].stored_best_times.y /* + 5 */,
			        goal_pair[1].stored_best_times.x);
//			int cur_middle = (goal_pair[0].stored_best_times.y +
//			    goal_pair[1].stored_best_times.x) >> 1;
			cur_goals[0].letter_bonus = 200;
			cur_goals[1].letter_bonus = 200;

			auto p_first = Problem (p.name,
			    p.contents[0..cur_middle]);

			if (cur_goals[0].word !in lower_cache)
			{
				auto game = new Game (p_first, t, s);
				game.goals = [cur_goals[0]];
				cur_goals[0].row = Board.SIZE - 1;
				game.bias = -bias;
				stderr.writefln ("%s %s %s %(%s\n    %)",
				    p.name,
				    beam_width, beam_depth, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				lower_cache[cur_goals[0].word] = game.best;
			}
			auto lower_state = lower_cache[cur_goals[0].word];

			if (lower_state.board.score >=
			    cur_goals[0].score_rating)
			{
				auto game = new Game (p, t, s);
				game.goals = cur_goals;
				cur_goals[0].row = Board.SIZE - 1;
				cur_goals[1].row = 0;
				game.bias = +bias;
				stderr.writefln ("%s %s %s %(%s\n    %)",
				    p.name,
				    beam_width * 2, beam_depth, game.goals);
				stderr.flush ();
				game.play_from (beam_width * 2, beam_depth,
				    lower_state, Game.Keep.False);
				log_progress (game);
			}

			if (cur_goals[0].word !in upper_cache)
			{
				auto game = new Game (p_first, t, s);
				game.goals = [cur_goals[0]];
				cur_goals[0].row = 0;
				game.bias = +bias;
				stderr.writefln ("%s %s %s %(%s\n    %)",
				    p.name,
				    beam_width, beam_depth, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				upper_cache[cur_goals[0].word] = game.best;
			}
			auto upper_state = upper_cache[cur_goals[0].word];

			if (upper_state.board.score >=
			    cur_goals[0].score_rating)
			{
				auto game = new Game (p, t, s);
				game.goals = cur_goals;
				cur_goals[0].row = 0;
				cur_goals[1].row = Board.SIZE - 1;
				game.bias = -bias;
				stderr.writefln ("%s %s %s %(%s\n    %)",
				    p.name,
				    beam_width * 2, beam_depth, game.goals);
				stderr.flush ();
				game.play_from (beam_width * 2, beam_depth,
				    upper_state, Game.Keep.False);
				log_progress (game);
			}
		}
	}
	return;

	foreach_reverse (i; 0..LET)
	{
		if (i != 'H' - 'A')
		{
			continue;
		}
		auto p = ps.problem[i];
/*
		if (m.best[p.short_name].board.score >= 2600)
		{
			continue;
		}
*/
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
//		    a.holes_rating < 50 &&
		    a.get_times.length > 2 &&
//		    a.get_times.length == Rack.MAX_SIZE &&
//		    a.get_times[2] >= a.get_times[0] - 5 &&
		    a.get_times[$ - 1] >= a.get_times[0] - 35 &&
		    a.score_rating >= 600).take (10))
		{
			auto goal = new Goal (goal_original);
			goal.stage = Goal.Stage.COMBINED;
			goal.row = Board.SIZE - 1;
			goal.letter_bonus = 100;
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
				stderr.writeln (p.name, ' ', bias, ' ', goal);
				stderr.flush ();

				game.bias = -bias;
				game.play (125, 0, Game.Keep.True);
				log_progress (game);
				if (game.best.board.score < 1000)
				{
					continue;
				}

				auto goals2 = goals.dup;
				foreach (ref goal2; goals2)
				{
					goal2 = new Goal (goal2);
//					goal2.row = Board.SIZE - 1;
				}
				foreach (ref goal2; goals2)
				{
					goal2.stored_best_times =
					    goal2.calc_best_times
					    (TileBag (p),
					    MIDDLE, TOTAL_TILES);
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
//				    a.holes_rating < 50 &&
				    a.get_times.length > 1 &&
//				    a.get_times.length == Rack.MAX_SIZE &&
//				    a.get_times[2] >= a.get_times[0] - 5 &&
				    a.get_times[$ - 1] >=
				    a.get_times[0] - 35 &&
				    a.score_rating +
				    goal.score_rating >= 1500).take (10))
				{
					auto goal2 = new Goal (goal2_original);
					goal2.stage = Goal.Stage.COMBINED;
					goal2.row = 0;
					goal2.letter_bonus = 100;
					goal.letter_bonus = 200;
					scope (exit)
					{
						goal.letter_bonus = 100;
					}
					stderr.writeln (p.name, ' ', goal2);
					stderr.flush ();

					game.bias = +bias;
					game.goals = [goal, goal2];
					game.problem = p;
					game.resume (250, 0, MIDDLE /* - 10 */,
					    Game.Keep.True, true);
					log_progress (game);
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
