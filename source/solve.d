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
import tools;
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

void put_one (int new_beam_width, int new_beam_depth, int new_bias,
    Problem p, Trie t, Scoring s, Goal [] goals,
    Goal [] prev_goals = null, GameMove prev_guide = null)
{
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

	foreach (loop_goal; goals_main.take (1))
	{
		stderr.writefln ("%s %s", p.name, loop_goal);
		stderr.flush ();
		auto cur_goals = [loop_goal];
		foreach (ref temp_goal; cur_goals)
		{
			temp_goal = new Goal (temp_goal);
		}

		int beam_width = new_beam_width;
		int beam_depth = new_beam_depth;
		int bias = new_bias;
		int cur_middle = TOTAL_TILES;
		cur_goals[0].letter_bonus = 100;

		auto p_first = Problem (p.name,
		    p.contents[0..cur_middle]);
		auto p_first_clean = Problem.clean (p_first);
		auto p_clean = Problem.clean (p);

		GameState lower_state;
		if (true)
		{
			auto game = new Game (p_first_clean, t, s);
			game.goals = prev_goals ~ [cur_goals[0]];
			cur_goals[0].row = Board.SIZE - 1;
			game.bias = -bias;
			game.moves_guide = prev_guide;
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
			auto game = new Game (p_first_clean, t, s);
			game.goals = prev_goals ~ [cur_goals[0]];
			cur_goals[0].row = 0;
			game.bias = +bias;
			game.moves_guide = prev_guide;
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

void put_goal_pairs (int new_beam_width, int new_beam_depth,
    int new_bias0, int new_bias1,
    Problem p, Trie t, Scoring s, Goal [] [] goal_pairs,
    Goal [] prev_goals = null, GameMove prev_guide = null)
{
//	GameState [ByteString] lower_cache;
//	GameState [ByteString] upper_cache;
	foreach (counter, goal_pair; goal_pairs)
	{
		if (counter < 23)
		{
			continue;
		}
		stderr.writefln ("%s %(%s\n    %)", p.name, goal_pair);
		stderr.flush ();
		auto cur_goals = goal_pair.dup;
		foreach (ref goal; cur_goals)
		{
			goal = new Goal (goal);
			goal.stage = Goal.Stage.COMBINED;
		}

		int beam_width = new_beam_width;
		int beam_depth = new_beam_depth;
		int cur_middle = max (goal_pair[0].stored_best_times.y,
		    goal_pair[1].stored_best_times.x, TOTAL_TILES / 2);
		cur_goals[0].letter_bonus = 100;
		cur_goals[1].letter_bonus = 100;

		auto p_first = Problem (p.name,
		    p.contents[0..cur_middle]);
		auto p_first_clean = Problem.clean (p_first);
		auto p_clean = Problem.clean (p);

		auto p_restricted = Problem.restrict_back
		    (p_clean, cur_goals[1].word);
		auto p_first_restricted = Problem (p.name,
		    p_restricted.contents[0..cur_middle]);

		void do_it (byte row0, byte row1, int bias0, int bias1,
		    ref GameState [ByteString] cache)
		{
			if (cur_goals[0].word !in cache)
			{
				auto game =
				    new Game (p_first_restricted, t, s);
				game.goals = prev_goals ~ [cur_goals[0]];
				cur_goals[0].row = row0;
				cur_goals[1].row = row1;
				game.bias = bias0;
				game.moves_guide = prev_guide;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				cache[cur_goals[0].word] = game.best;
			}
			auto inner_state = cache[cur_goals[0].word];

			GameState cur_state;
			if (inner_state.board.is_row_filled (0) ||
			    inner_state.board.is_row_filled (Board.SIZE - 1))
			{
				auto complete_guide = GameMove.invert
				    (inner_state.closest_move);
				log_guide (complete_guide, "complete");

				auto game = new Game (p_clean, t, s);
				auto temp_history = game.reduce_move_history
				    (complete_guide);
				auto necessary_guide = temp_history[0];
				auto p_restricted = temp_history[1];
				log_guide (necessary_guide, "necessary");

				game.goals = [cur_goals[1]];
				cur_goals[0].row = row0;
				cur_goals[1].row = row1;
				game.bias = bias1;
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

			if (cur_state.board.is_row_filled (0) &&
			    cur_state.board.is_row_filled (Board.SIZE - 1))
			{
				auto complete_guide = GameMove.invert
				    (cur_state.closest_move);
				log_guide (complete_guide, "complete");

				auto game = new Game (p_clean, t, s);
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
			}
		}

/*
		do_it (Board.SIZE - 1, 0, -bias, lower_cache);

		do_it (0, Board.SIZE - 1, +bias, upper_cache);
*/

                GameState [ByteString] temp_cache1;
		do_it (Board.SIZE - 1, 0, -new_bias0, +new_bias1, temp_cache1);

                GameState [ByteString] temp_cache2;
		do_it (0, Board.SIZE - 1, +new_bias0, -new_bias1, temp_cache2);
	}
}

void put_two (int new_beam_width, int new_beam_depth,
    int new_bias0, int new_bias1,
    Problem p, Trie t, Scoring s, Goal [] goals1, Goal [] goals2,
    Goal [] prev_goals = null, GameMove prev_guide = null)
{
	auto goals_earliest = goals1.dup;
	foreach (ref cur_goal; goals_earliest)
	{
		cur_goal = new Goal (cur_goal);
		cur_goal.stored_best_times =
		    cur_goal.calc_earliest_times
		    (TileBag (p), 0, TOTAL_TILES);
		cur_goal.stored_times = cur_goal.calc_times
		    (TileBag (p),
		    cur_goal.stored_best_times.x,
		    cur_goal.stored_best_times.y);
	}
	goals_earliest = goals_earliest.filter
	    !(a => a.get_best_times.x != NA &&
//	      a.get_times[0] >= a.get_best_times.y - 14 &&
//	      a.get_times[0] - a.get_times[2] <= 14 &&
	      a.get_times[0] - a.get_times[$ - 1] <= TOTAL_TILES).array ();
	sort !((a, b) => a.stored_best_times < b.stored_best_times)
	    (goals_earliest);
	sort !((a, b) => a.score_rating > b.score_rating)
	    (goals_earliest);

	auto goals_latest = goals2.dup;
	foreach (ref cur_goal; goals_latest)
	{
		cur_goal = new Goal (cur_goal);
		cur_goal.stored_best_times =
		    cur_goal.calc_latest_times
		    (TileBag (p), 0, TOTAL_TILES);
		cur_goal.stored_times = cur_goal.calc_times
		    (TileBag (p),
		    cur_goal.stored_best_times.x,
		    cur_goal.stored_best_times.y);
	}
	goals_latest = goals_latest.filter
	    !(a => a.get_best_times.x != NA &&
//	      a.get_times[0] >= a.get_best_times.y - 14 &&
//	      a.get_times[0] - a.get_times[2] <= 14 &&
	      a.get_times[0] - a.get_times[$ - 1] <= TOTAL_TILES).array ();
	sort !((a, b) => a.stored_best_times > b.stored_best_times)
	    (goals_latest);
	sort !((a, b) => a.score_rating > b.score_rating)
	    (goals_latest);

	auto p_clean = Problem.clean (p);
	auto initial_state = GameState (p_clean);

	immutable int SLACK = TOTAL_TILES;
	Goal [] [] goal_pairs;
	foreach (goal1; goals_earliest.take (1250))
	{
		foreach (goal2; goals_latest.take (1250))
		{
			// first check
			if (goal1.get_best_times.y -
			    goal2.get_best_times.x > SLACK)
			{
				continue;
			}

			// second check
			TileCounter goals_counter;
			foreach (letter; goal1.word)
			{
				goals_counter[letter]++;
			}
			foreach (letter; goal2.word)
			{
				goals_counter[letter]++;
			}
			if (!(goals_counter << initial_state.tiles.counter))
			{
				continue;
			}

			// third check
			auto p_restricted = Problem.restrict_back
			    (p, goal2.word);
			auto p_first_restricted = Problem (p.name,
			    p_restricted.contents[0..goal1.get_best_times.y]);
			if (p_first_restricted.count_restricted () >
			    Rack.MAX_SIZE - goal1.count_forbidden ())
			{
				continue;
			}

			// include the pair
			goal_pairs ~= [goal1, goal2];
		}
	}
	stderr.writeln ("Goal pairs for ", p.name, ' ', goal_pairs.length);
	stderr.flush ();

	sort !((a, b) => a[0].score_rating + a[1].score_rating +
	    max (a[0].score_rating, a[1].score_rating) >
	    b[0].score_rating + b[1].score_rating +
	    max (b[0].score_rating, b[1].score_rating), SwapStrategy.stable)
	    (goal_pairs);
	sort !((a, b) => a[0].score_rating + a[1].score_rating >
	    b[0].score_rating + b[1].score_rating, SwapStrategy.stable)
	    (goal_pairs);

	put_goal_pairs (new_beam_width, new_beam_depth,
	    new_bias0, new_bias1, p, t, s,
	    goal_pairs.take (50).array (), prev_goals, prev_guide);
}

void main (string [] args)
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
//	auto t = new Trie (read_all_lines ("data/words8.txt"), 233_691);
	auto s = new Scoring ();
	global_scoring = s;
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
/*
	{
		auto goals_center = GoalBuilder.build_center_goals (t);
		writefln ("%(%s\n%)", goals_center);
		auto goals_center2 = GoalBuilder.build_fat_center_goals
		    (read_all_lines ("data/goals-center-full.txt"));
		sort !((a, b) => a.possible_masks.length >
		    b.possible_masks.length) (goals_center2);
		foreach (goal; goals_center2)
		{
			writefln ("%s %s %s", goal, goal.mask_forbidden,
			    goal.possible_masks.length);
		}
		return;
	}
*/
	auto goals_relaxed = GoalBuilder.build_fat_goals
	    (read_all_lines ("data/goals.txt"), false);
	foreach (ref goal; goals_relaxed)
	{
		goal.stage = Goal.Stage.GREEDY;
		goal.stored_score_rating = goal.calc_score_rating (s);
	}

	auto goals = GoalBuilder.build_fat_goals
	    (read_all_lines ("data/goals.txt"), true);
	foreach (ref goal; goals)
	{
		goal.stage = Goal.Stage.COMBINED;
		goal.stored_score_rating = goal.calc_score_rating (s);
	}

	auto goals_center = GoalBuilder.build_fat_center_goals
	    (read_all_lines ("data/goals-center-full.txt"));
	foreach (ref goal; goals_center)
	{
		goal.row = Board.CENTER;
		goal.stage = Goal.Stage.CENTER;
		goal.stored_score_rating = goal.calc_score_rating (s);
	}

	auto m = new Manager (ps);
	GC.collect ();

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

	version (extract)
	{
		m.extract_log ("log.txt");
		foreach (c; 1..100)
		{
			m.extract_log ("log" ~ to !(string) (c) ~ ".txt");
		}
		m.close ();
		return;
	}

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
		if (i != 'G' - 'A')
		{
			continue;
		}
		auto p = ps.problem[i];

		put_two (2500, 0, 2, 5, p, t, s,
		    goals_relaxed, goals, [], null);
//		put_two (1250, 0, 8, p, t, s,
//		    goals_relaxed, goals, [], null);

/*
		auto goals_middle = goals_center.dup;
		foreach (ref cur_goal; goals_middle)
		{
			cur_goal = new Goal (cur_goal);
			cur_goal.stored_best_times =
			    cur_goal.calc_earliest_times
			    (TileBag (p), 0, TOTAL_TILES);
			cur_goal.stored_times = cur_goal.calc_times
			    (TileBag (p),
			    cur_goal.stored_best_times.x,
			    cur_goal.stored_best_times.y);
		}
		sort !((a, b) => a.score_rating > b.score_rating,
		    SwapStrategy.stable)
		    (goals_middle);
		sort !((a, b) => a.stored_best_times.y <
		    b.stored_best_times.y, SwapStrategy.stable)
		    (goals_middle);
		sort !((a, b) => a.possible_masks.length >
		    b.possible_masks.length, SwapStrategy.stable)
		    (goals_middle);

		foreach (loop_goal; goals_middle.take (52))
//		foreach (loop_goal; goals_middle.take (250))
		{
			stderr.writefln ("%s %s", p.name, loop_goal);
			stderr.flush ();
			auto cur_goals = [loop_goal];
			foreach (ref temp_goal; cur_goals)
			{
				temp_goal = new Goal (temp_goal);
			}
			
			int beam_width = 50;
			int beam_depth = 0;
			int bias = 0;
			int cur_middle = loop_goal.stored_best_times.y;
			cur_goals[0].letter_bonus = 100;

			auto p_first = Problem (p.name,
			    p.contents[0..cur_middle]);

			GameState middle_state;
			if (true)
			{
				auto game = new Game (p_first, t, s);
				game.goals = [cur_goals[0]];
				game.bias = 0;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    Game.Keep.False);
				log_progress (game);
				middle_state = game.best;
			}

			if (true)
			{
				auto middle_complete_guide = GameMove.invert
				    (middle_state.closest_move);

				auto game = new Game (p, t, s);
				auto temp_history = game.reduce_move_history
				    (middle_complete_guide);
				auto middle_necessary_guide = temp_history[0];
				auto p_restricted = temp_history[1];

				int middle_tiles_total = GameTools.tiles_total
				    (middle_necessary_guide);
				int middle_tiles_peak = GameTools.tiles_peak
				    (middle_necessary_guide);
				if (0 < middle_tiles_total &&
				    middle_tiles_total < 20 &&
				    middle_tiles_peak <= 5)
				{
					log_guide (middle_complete_guide,
					    "complete");
					log_guide (middle_necessary_guide,
					    "necessary");
					stderr.writeln (middle_tiles_total,
					    ' ', middle_tiles_peak);
					stderr.flush ();
//					put_one (250, 0, 8,
//					    p_restricted, t, s,
//					    goals, cur_goals, null);
//					put_two (1250, 0, 5,
//					    p_restricted, t, s,
//					    goals_relaxed, goals,
//					    cur_goals, null);
					put_two (1250, 0, 12,
					    p_restricted, t, s,
					    goals_relaxed, goals,
					    [], middle_necessary_guide);
	                	}
			}
		}
*/
	}
}
