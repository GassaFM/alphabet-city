module main;

import core.memory;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.math;
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

void log_guide (GameMove start_move, string name = "a")
{
	GameMove [] gm1;
	for (GameMove cur_move = start_move; cur_move !is null;
	    cur_move = cur_move.chained_move)
	{
		gm1 ~= cur_move;
	}
	stderr.writefln ("%s guide (%s): %(%s, %)", name, gm1.length, gm1);
	stderr.flush ();
}

void main (string [] args)
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
//	auto t = new Trie (read_all_lines ("data/words8.txt"), 233_691);
	auto s = new Scoring ();
	global_scoring = s;
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
	auto goals = GoalBuilder.build_fat_goals
	    (read_all_lines ("data/goals.txt"), true);
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
			auto complete_guide = GameMove.invert
			    (temp.closest_move);
			stderr.writeln (p.name, ' ', temp.board.score);
			stderr.flush ();

			GameMove [] gm1;
			for (GameMove cur_move = complete_guide;
			    cur_move !is null;
			    cur_move = cur_move.chained_move)
			{
				gm1 ~= cur_move;
			}
			stderr.writefln ("complete guide (%s): %(%s, %)",
			    gm1.length, gm1);
			stderr.flush ();

			auto temp_history = game.reduce_move_history
			    (complete_guide);
			auto necessary_guide = temp_history[0];
			auto p_restricted = temp_history[1];

			GameMove [] gm2;
			for (GameMove cur_move = necessary_guide;
			    cur_move !is null;
			    cur_move = cur_move.chained_move)
			{
				gm2 ~= cur_move;
			}
			stderr.writefln ("necessary guide (%s): %(%s, %)",
			    gm2.length, gm2);
			stderr.flush ();

			game.moves_guide = necessary_guide;
			game.problem = p_restricted;
			game.forced_lock_wildcards = true;
			int beam_width = 1500;
			int beam_depth = 0;
			stderr.writefln ("%s w=%s d=%s", p.name,
			    beam_width, beam_depth);
			stderr.flush ();
			game.play (beam_width, beam_depth, Game.Keep.False);
			log_progress (game);
		}
		return;
	}

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
			stderr.writefln ("%s w=%s d=%s b=%s %(%s\n    %)",
			    p.name, beam_width, beam_depth, bias,
			    game.goals);
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
			stderr.writefln ("%s w=%s d=%s b=%s %(%s\n    %)",
			    p.name, beam_width, beam_depth, bias,
			    game.goals);
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
			stderr.writefln ("%s w=%s d=%s b=%s %(%s\n    %)",
			    p.name, beam_width, beam_depth, bias,
			    game.goals);
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
			stderr.writefln ("%s w=%s d=%s b=%s %(%s\n    %)",
			    p.name, beam_width, beam_depth, bias,
			    game.goals);
			stderr.flush ();
			game.resume (beam_width * 2, beam_depth,
			    cur_middle /* - 10 */, Game.Keep.False,
			    true, false, true);
			log_progress (game);
		}
		while (false);

		return;
	}

	foreach (i; 0..LET)
	{
		auto p = ps.problem[i];

		auto goals_main = goals.dup;
		foreach (ref cur_goal; goals_main)
		{
			cur_goal = new Goal (cur_goal);
			cur_goal.stored_best_times =
			    cur_goal.calc_best_times
			    (TileBag (p), 0, TOTAL_TILES);
			cur_goal.stored_times = cur_goal.calc_times
			    (TileBag (p),
			    cur_goal.stored_best_times.x,
			    cur_goal.stored_best_times.y);
		}
		sort !((a, b) => a.score_rating > b.score_rating)
		    (goals_main);

		foreach (loop_goal; goals_main.take (10))
		{
			stderr.writefln ("%s %s", p.name, loop_goal);
			stderr.flush ();
			auto cur_goals = [loop_goal];
			foreach (ref temp_goal; cur_goals)
			{
				temp_goal = new Goal (temp_goal);
			}

			int beam_width = 500;
			int beam_depth = 0;
			int bias = 8;
			int cur_middle = TOTAL_TILES;
			cur_goals[0].letter_bonus = 100;

			auto p_first = Problem (p.name,
			    p.contents[0..cur_middle]);

			GameState lower_state;
			if (true)
			{
				auto game = new Game (p_first, t, s);
				game.goals = [cur_goals[0]];
				cur_goals[0].row = Board.SIZE - 1;
				game.bias = -bias;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				lower_state = game.best;
			}

			GameState upper_state;
			if (true)
			{
				auto game = new Game (p_first, t, s);
				game.goals = [cur_goals[0]];
				cur_goals[0].row = 0;
				game.bias = +bias;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				upper_state = game.best;
			}
		}
	}
	return;

	foreach (i; 0..LET)
	{
		if (i != 'X' - 'A')
		{
			continue;
		}
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

		immutable int SLACK = 0;
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
		immutable int PERMIT = 100;
/*
		sort !((a, b) => a[0].score_rating + a[1].score_rating -
		    abs (a[0].stored_best_times.x + PERMIT - 50) * 25 >
		    b[0].score_rating + b[1].score_rating -
		    abs (b[0].stored_best_times.x + PERMIT - 50) * 25)
		    (goal_pairs);
*/
		sort !((a, b) => a[0].score_rating + a[1].score_rating >
		    b[0].score_rating + b[1].score_rating)
		    (goal_pairs);

		GameState [ByteString] lower_cache;
		GameState [ByteString] upper_cache;
		foreach (goal_pair; goal_pairs.take (50))
		{
			stderr.writefln ("%s %(%s\n    %)", p.name, goal_pair);
			stderr.flush ();
			auto cur_goals = goal_pair.dup;
			foreach (ref goal; cur_goals)
			{
				goal = new Goal (goal);
			}

			int beam_width = 1500;
			int beam_depth = 0;
			int bias = 7;
//			int cur_middle = goal_pair[0].stored_best_times.y;
			int cur_middle =
			    min (goal_pair[0].stored_best_times.y + PERMIT,
			        goal_pair[1].stored_best_times.x);
//			int cur_middle = (goal_pair[0].stored_best_times.y +
//			    goal_pair[1].stored_best_times.x) >> 1;
			cur_goals[0].letter_bonus = 100;
			cur_goals[1].letter_bonus = 100;

			auto p_first = Problem (p.name,
			    p.contents[0..cur_middle]);
			GameState cur_state;

			if (cur_goals[0].word !in lower_cache)
			{
				auto game = new Game (p_first, t, s);
				game.goals = [cur_goals[0]];
				cur_goals[0].row = Board.SIZE - 1;
				game.bias = -bias;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				lower_cache[cur_goals[0].word] = game.best;
			}
			auto lower_state = lower_cache[cur_goals[0].word];
/*
			writeln ("Best lower state:");
			writeln (lower_state);
*/

			cur_state = GameState.init;
			if (lower_state.board.score >=
			    cur_goals[0].score_rating)
			{
				auto complete_guide = GameMove.invert
				    (lower_state.closest_move);
				log_guide (complete_guide, "complete");

				auto game = new Game (p, t, s);
				auto temp_history = game.reduce_move_history
				    (complete_guide);
				auto necessary_guide = temp_history[0];
				auto p_restricted = temp_history[1];
				log_guide (necessary_guide, "necessary");

				game.goals = [cur_goals[1]];
				cur_goals[0].row = Board.SIZE - 1;
				cur_goals[1].row = 0;
				game.bias = +bias;
				game.moves_guide = necessary_guide;
				game.problem = p_restricted;
				game.forced_lock_wildcards = true;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				cur_state = game.best;
			}

			if (cur_state.board.score >=
			    cur_goals[0].score_rating +
			    cur_goals[1].score_rating)
			{
				auto complete_guide = GameMove.invert
				    (cur_state.closest_move);
				log_guide (complete_guide, "complete");

				auto game = new Game (p, t, s);
				auto temp_history = game.reduce_move_history
				    (complete_guide);
				auto necessary_guide = temp_history[0];
				auto p_restricted = temp_history[1];
				log_guide (necessary_guide, "necessary");

				game.bias = 0;
				game.moves_guide = necessary_guide;
				game.problem = p_restricted;
				game.forced_lock_wildcards = true;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width * 4,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width * 4, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				cur_state = GameState.init;
			}

			if (cur_goals[0].word !in upper_cache)
			{
				auto game = new Game (p_first, t, s);
				game.goals = [cur_goals[0]];
				cur_goals[0].row = 0;
				game.bias = +bias;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				upper_cache[cur_goals[0].word] = game.best;
			}
			auto upper_state = upper_cache[cur_goals[0].word];
/*
			writeln ("Best upper state:");
			writeln (upper_state);
*/

			cur_state = GameState.init;
			if (upper_state.board.score >=
			    cur_goals[0].score_rating)
			{
				auto complete_guide = GameMove.invert
				    (upper_state.closest_move);
				log_guide (complete_guide, "complete");

				auto game = new Game (p, t, s);
				auto temp_history = game.reduce_move_history
				    (complete_guide);
				auto necessary_guide = temp_history[0];
				auto p_restricted = temp_history[1];
				log_guide (necessary_guide, "necessary");

				game.goals = [cur_goals[1]];
				cur_goals[0].row = 0;
				cur_goals[1].row = Board.SIZE - 1;
				game.bias = -bias;
				game.moves_guide = necessary_guide;
				game.problem = p_restricted;
				game.forced_lock_wildcards = true;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				cur_state = game.best;
			}

			if (cur_state.board.score >=
			    cur_goals[0].score_rating +
			    cur_goals[1].score_rating)
			{
				auto complete_guide = GameMove.invert
				    (cur_state.closest_move);
				log_guide (complete_guide, "complete");

				auto game = new Game (p, t, s);
				auto temp_history = game.reduce_move_history
				    (complete_guide);
				auto necessary_guide = temp_history[0];
				auto p_restricted = temp_history[1];
				log_guide (necessary_guide, "necessary");

				game.bias = 0;
				game.moves_guide = necessary_guide;
				game.problem = p_restricted;
				game.forced_lock_wildcards = true;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width * 4,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width * 4, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				cur_state = GameState.init;
			}
		}
	}
}
