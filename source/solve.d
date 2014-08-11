module main;

import core.bitop;
import core.memory;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.math;
import std.random;
import std.range;
import std.stdio;
import std.string;
import std.typecons;

import board;
import game;
import game_complex;
import game_move;
import game_state;
import fifteen;
import general;
import goal;
import improve;
import manager;
import plan;
import problem;
import scoring;
import tile_bag;
import tools;
import trie;

void log_progress (GameComplex game)
{
	static bool started_output = false;

	stderr.writeln (game.problem.name, ' ',
	    game.best.board.score, " (",
	    game.best.board.value, ')');
	stderr.flush ();
	if (game.best.board.score < 2600 ||
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

void log_progress (Problem problem, GameState cur)
{
	static bool started_output = false;

	cur.board.normalize ();
	stderr.writeln (problem.name, ' ',
	    cur.board.score, " (",
	    cur.board.value, ')', " [",
	    cur.board.total, "]");
	stderr.flush ();
	if (cur.board.score < 2600 ||
	    cur.tiles.contents.length < TOTAL_TILES)
	{
		return;
	}
	if (started_output)
	{
		writeln (';');
	}
	started_output = true;
	writeln (problem.name);
	writeln (cur.moves_string ());
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
			auto game = new GameComplex (p_first_clean, t, s);
			game.goals = prev_goals ~ [cur_goals[0]];
			cur_goals[0].row = Board.SIZE - 1;
			game.bias = -bias;
			game.moves_guide = prev_guide;
			stderr.writefln ("%s w=%s d=%s b=%s " ~
			    "%(%s\n    %)", p.name, beam_width,
			    beam_depth, game.bias, game.goals);
			stderr.flush ();
			game.play (beam_width, beam_depth,
			    GameComplex.Keep.False);
			log_progress (game);
			lower_state = game.best;
		}

		GameState upper_state;
		if (true)
		{
			auto game = new GameComplex (p_first_clean, t, s);
			game.goals = prev_goals ~ [cur_goals[0]];
			cur_goals[0].row = 0;
			game.bias = +bias;
			game.moves_guide = prev_guide;
			stderr.writefln ("%s w=%s d=%s b=%s " ~
			    "%(%s\n    %)", p.name, beam_width,
			    beam_depth, game.bias, game.goals);
			stderr.flush ();
			game.play (beam_width, beam_depth,
			    GameComplex.Keep.False);
			log_progress (game);
			upper_state = game.best;
		}
	}
}

int get_middle (const ref Goal [] goal_pair)
{
	return max (goal_pair[0].stored_best_times.y,
	    goal_pair[1].stored_best_times.x, TOTAL_TILES / 2);
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
		stderr.writefln ("%s sum=%s %(%s\n    %)", p.name,
		    goal_pair[0].score_rating + goal_pair[1].score_rating,
		    goal_pair);
		stderr.flush ();
		auto cur_goals = goal_pair.dup;
		foreach (ref goal; cur_goals)
		{
			goal = new Goal (goal);
			// TODO: let's now test without that line
			// TODO: try COMBINED; after that, if unsuccessful,
			//       try GREEDY when appropriate
//			goal.stage = Goal.Stage.COMBINED;
		}

		int beam_width = new_beam_width;
		int beam_depth = new_beam_depth;
		int cur_middle = get_middle (goal_pair);
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
				    new GameComplex (p_first_restricted, t, s);
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
				    GameComplex.Keep.False);
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

				auto game = new GameComplex (p_clean, t, s);
				auto temp_history = game.reduce_move_history
				    !((GameMove a) => true) (complete_guide);
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
				    GameComplex.Keep.False);
				log_progress (game);
				cur_state = game.best;
			}

			if (cur_state.board.is_row_filled (0) &&
			    cur_state.board.is_row_filled (Board.SIZE - 1))
			{
				auto complete_guide = GameMove.invert
				    (cur_state.closest_move);
				log_guide (complete_guide, "complete");

				auto game = new GameComplex (p_clean, t, s);
				auto temp_history = game.reduce_move_history
				    !((GameMove a) => true) (complete_guide);
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
				    GameComplex.Keep.False);
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
	    !(a => a.get_best_times.x != NA).array ();
//	    !(a => a.get_best_times.x != NA &&
//	      a.get_times[0] >= a.get_best_times.y - 14 &&
//	      a.get_times[0] - a.get_times[2] <= 14 &&
//	      a.get_times[0] - a.get_times[$ - 1] <= TOTAL_TILES).array ();
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
	    !(a => a.get_best_times.x != NA).array ();
//	    !(a => a.get_best_times.x != NA &&
//	      a.get_times[0] >= a.get_best_times.y - 14 &&
//	      a.get_times[0] - a.get_times[2] <= 14 &&
//	      a.get_times[0] - a.get_times[$ - 1] <= TOTAL_TILES).array ();
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
			version (debug_pairs)
			{
				writeln ("1>", goal1, "\n2>", goal2);
			}
			// first check
			if (goal1.get_best_times.y -
			    goal2.get_best_times.x > SLACK)
			{
				continue;
			}
			version (debug_pairs)
			{
				writeln ("passed 1");
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
			version (debug_pairs)
			{
				writeln ("passed 2");
			}

			auto cur_pair = [goal1, goal2];
			// third check
			auto p_restricted = Problem.restrict_back
			    (p, goal2.word);
			int cur_middle = get_middle (cur_pair);
			auto p_first_restricted = Problem (p.name,
			    p_restricted.contents[0..cur_middle]);
//			writeln (p_restricted);
//			writeln (p_first_restricted);
//			writeln (p_first_restricted.count_restricted ());
//			writeln (Rack.MAX_SIZE - goal1.count_forbidden ());
			if (p_first_restricted.count_restricted () >
			    Rack.MAX_SIZE - goal1.count_forbidden ())
			{
				continue;
			}
			version (debug_pairs)
			{
				writeln ("passed 3");
			}

			// include the pair
			goal_pairs ~= cur_pair;
			version (debug_pairs)
			{
				writeln (cur_pair[0].score_rating +
				    cur_pair[1].score_rating);
			}
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
	    goal_pairs.take (15).drop (0).array (), prev_goals, prev_guide);
}

void generate_all_goals (Trie trie)
{
	auto goals_all = GoalBuilder.build_all_goals (trie);
	foreach (cur_goal; goals_all)
	{
		enforce (cur_goal.score_rating >= 0); // to calculate
		writeln (cur_goal, ' ',
		    ((cur_goal.mask_forbidden >> Board.CENTER) & 1));
	}
}

void generate_triples (Trie trie, Problem problem)
{
	TileCounter cp;
	cp.account (problem.contents);

	auto lw = read_all_lines ("data/goals/long-words.txt");
	long num1 = 0;
	long num2 = 0;
	long num3 = 0;
	foreach (w0; lw)
	{
		TileCounter c0;
		c0.account (w0);
		if (!(c0 << cp))
		{
			continue;
		}
		num1++;

		foreach (w1; lw)
		{
			TileCounter c1 = c0;
			c1.account (w1);
			if (!(c1 << cp))
			{
				continue;
			}
			num2++;

			foreach (w2; lw)
			{
				TileCounter c2 = c1;
				c2.account (w2);
				if (!(c2 << cp))
				{
					continue;
				}
				num3++;
			}
		}
	}
	writeln (num1, ' ', num2, ' ', num3);
}

bool run_plan (Trie t, Scoring s, Manager m, ref Plan plan,
    int max_score_gap, int refine_steps,
    int start_width, int max_width, int delta_width, int cur_depth)
{
	auto p = plan.problem;
	auto game = new Game !(Trie) (t, s, plan);
	auto start = GameState (p);
	start.tiles.target_board = plan.target_board;
	int prev_score = m.best[p.short_name].board.score - max_score_gap;

	bool found = false;
	foreach (step; 0..refine_steps)
	{
		int cur_width = start_width + uniform !("[]")
		    (0, delta_width, random_gen);
		stderr.writeln (plan);
		stderr.writeln ("refine step: ", step + 1);
		stderr.flush ();
		auto next = game_beam_search
		    ([start], game, cur_width, cur_depth);
		log_progress (p, next);
		if (next.board.total >= TOTAL_TILES - 2)
		{
			if (next.board.score < prev_score)
			{
				return true;
			}
			found = true;
			break;
		}
		next.board.normalize ();
		plan.refine (next.board);
	}
	if (refine_steps == 0)
	{
		found = true;
	}
	else
	{
		start_width <<= 1;
	}
	if (!found)
	{
		return false;
	}

	for (int width = start_width; width <= max_width; width <<= 1)
	{
		int cur_width = width + uniform !("[]")
		    (0, delta_width, random_gen);
		stderr.writeln (plan);
		stderr.flush ();
		auto next = game_beam_search
		    ([start], game, cur_width, cur_depth);
		log_progress (p, next);
		next.board.normalize ();
		if (!next.board.is_row_filled (0) &&
		    !next.board.is_row_filled (Board.CENTER) &&
		    !next.board.is_row_filled (Board.SIZE - 1))
		{
			break;
		}
		if (prev_score < next.board.score)
		{
			prev_score = next.board.score;
		}
		else
		{
			break;
		}
	}

	GC.collect ();
	return true;
}

void put_two_plan (Trie t, Scoring s, Problem p, Manager m,
    Goal [] [2] all_goals)
{
	auto random = new Random (123456);
	Plan [] plans;

	static immutable int MAX_PLANS_LENGTH = 10_000_000;
	static immutable int MAX_GOALS = 5849; // 891
	static immutable int MIN_SCORE_RATING = 2250;
	static immutable int MAX_SCORE_GAP = 150;
	static immutable int MAX_REFINE_STEPS = 5;
	static immutable int START_WIDTH = 1000;
	static immutable int MAX_WIDTH = 8000;
	static immutable int DELTA_WIDTH = 50;
	static immutable int MAX_DEPTH = 0;
	static immutable int MAX_SIMILAR_PLANS = 9999;
	static immutable int MAX_CHECK_POINTS = 99;
	static immutable int MAX_COUNTER = 210;
	static immutable int PLANS_TO_DROP = 0;
	
	TileCounter total_counter = GameState (p).tiles.counter;
	bool try_plan (Plan plan)
	{
		if (plan.score_rating != NA &&
		    plan.score_rating >= MIN_SCORE_RATING)
		{
			plans ~= plan;
			return (plans.length >= MAX_PLANS_LENGTH);
		}
		return false;
	}

	first_loop:
	foreach (num1, pre_goal1; all_goals[1].take (MAX_GOALS))
	{
		auto goal1 = new Goal (pre_goal1);
		goal1.row = 0;

		TileCounter counter1;
		foreach (let; goal1.word)
		{
			counter1[let & LET_MASK]++;
		}
		if (!(total_counter >>> counter1))
//		if (!(counter1 << total_counter))
		{
			continue;
		}

		foreach (num2, pre_goal2; all_goals[1].take (num1))
		{
			if (goal1.score_rating + pre_goal2.score_rating <
			    MIN_SCORE_RATING)
			{
				break;
			}

			auto goal2 = new Goal (pre_goal2);
			goal2.row = Board.SIZE - 1;

			TileCounter counter2 = counter1;
			foreach (let; goal2.word)
			{
				counter2[let & LET_MASK]++;
			}
			if (!(total_counter >>> counter2))
//			if (!(counter2 << total_counter))
			{
				continue;
			}

			if (try_plan (new Plan (p, [goal1, goal2])))
			{
				break first_loop;
			}

			if (try_plan (new Plan (p, [goal2, goal1])))
			{
				break first_loop;
			}

			swap (goal1.row, goal2.row);
			scope (exit)
			{
				swap (goal1.row, goal2.row);
			}

			if (try_plan (new Plan (p, [goal1, goal2])))
			{
				break first_loop;
			}

			if (try_plan (new Plan (p, [goal2, goal1])))
			{
				break first_loop;
			}
		}
	}
	GC.collect ();

	sort !((a, b) => a.score_rating > b.score_rating ||
	    (a.score_rating == b.score_rating &&
	    a.sketch_value > b.sketch_value),
//	    a.check_points.length < b.check_points.length),
	    SwapStrategy.stable) (plans);
	stderr.writeln ("Problem ", p.name, ' ', plans.length, ' ',
	    plans.length > 0 ? plans[0].score_rating : -1, ' ',
	    plans.length > 0 ? plans[$ - 1].score_rating : -1);
	stderr.flush ();

	int counter = 0;
	int [ulong] visited;
	static immutable int PRIME = 262_139;
	foreach (plan; plans.drop (PLANS_TO_DROP))
	{
		if (plan.check_points.length > MAX_CHECK_POINTS)
		{
			continue;
		}
/*
		if (plan.problem.contents.find ('{').empty)
		{ // leave only plans with wildcards
			continue;
		}
*/
		
		ulong cur_hash = 0;
		foreach (goal_move; plan.goal_moves)
		{
			foreach (tile; goal_move.word)
			{
				cur_hash = cur_hash * PRIME +
				    (tile & LET_MASK);
			}
			cur_hash = cur_hash * PRIME + goal_move.row;
			cur_hash = cur_hash * PRIME + goal_move.col;
		}

		visited[cur_hash]++;
//		writeln (visited);
		if (visited[cur_hash] > MAX_SIMILAR_PLANS)
		{
/*		
			if (uniform (0, visited[cur_hash], random))
			{
				continue;
			}
*/
			continue;
		}

		stdout.writeln ("Entry: ", counter + 1);
		stdout.flush ();
		stderr.writeln ("Entry: ", counter + 1);
		stderr.flush ();
		run_plan (t, s, m, plan, MAX_SCORE_GAP, MAX_REFINE_STEPS,
		    START_WIDTH, MAX_WIDTH, DELTA_WIDTH, MAX_DEPTH);

		counter++;
		if (counter >= MAX_COUNTER)
		{
			break;
		}
	}
}

void put_three_plan (Trie t, Scoring s, Problem p, Manager m,
    Goal [] [2] all_goals)
{
	auto random = new Random (1234567);
	alias FatPlan = Tuple !(Plan, "plan", Goal, "goal1", Goal, "goal2");
	FatPlan [] plans;

	static immutable int MAX_PLANS_LENGTH = 10_000_000;
	static immutable int MAX_GOALS = 5849; // 891
	static immutable int MIN_SCORE_RATING = 2250;
	static immutable int MAX_SCORE_GAP = 150;
	static immutable int MAX_REFINE_STEPS = 3;
	static immutable int START_WIDTH = 250;
	static immutable int MAX_WIDTH = 250;
	static immutable int DELTA_WIDTH = 50;
	static immutable int MAX_DEPTH = 0;
	static immutable int MAX_SIMILAR_PLANS = 1;
	static immutable int MAX_CHECK_POINTS = 8;
	static immutable int MAX_COUNTER = 300;
	static immutable int PLANS_TO_DROP = 0;

	static immutable int MAX_CENTER_REFINE_STEPS = 12;
	static immutable int START_CENTER_WIDTH = 250;
	static immutable int MAX_CENTER_WIDTH = 2000;
	static immutable int DELTA_CENTER_WIDTH = 50;
	static immutable int MAX_CENTER_DEPTH = 0;
	static immutable int MAX_CENTER_GOALS = 1_000_000;
	static immutable int MAX_INNER_COUNTER = 300;
	static immutable int MAX_CENTER_FORBIDDEN = 7;
	static immutable int MIN_FIRST_MOVE = 1;
	static immutable int MAX_ADDED_CHECK_POINTS = 2;

	bool try_plan (Plan plan, Goal goal1, Goal goal2)
	{
		if (plan.score_rating != NA &&
		    plan.score_rating >= MIN_SCORE_RATING)
		{
			plans ~= FatPlan (plan,
			    new Goal (goal1), new Goal (goal2));
			return (plans.length >= MAX_PLANS_LENGTH);
		}
		return false;
	}

	TileCounter total_counter = GameState (p).tiles.counter;
	TileCounter start_counter =
	    GameState (Problem (p.name, p.contents[0..Rack.MAX_SIZE]))
	    .tiles.counter;

	first_loop:
	foreach (num1, pre_goal1; all_goals[1].take (MAX_GOALS))
	{
		auto goal1 = new Goal (pre_goal1);
		goal1.row = 0;

		TileCounter counter1;
		foreach (let; goal1.word)
		{
			counter1[let & LET_MASK]++;
		}
		if (!(total_counter >>> counter1))
//		if (!(counter1 << total_counter))
		{
			continue;
		}

		foreach (num2, pre_goal2; all_goals[1].take (num1))
		{
			if (goal1.score_rating + pre_goal2.score_rating <
			    MIN_SCORE_RATING)
			{
				break;
			}

			auto goal2 = new Goal (pre_goal2);
			goal2.row = Board.SIZE - 1;

			TileCounter counter2 = counter1;
			foreach (let; goal2.word)
			{
				counter2[let & LET_MASK]++;
			}
			if (!(total_counter >>> counter2))
//			if (!(counter2 << total_counter))
			{
				continue;
			}

			if (try_plan (new Plan (p, [goal1, goal2]),
			    goal1, goal2))
			{
				break first_loop;
			}

			if (try_plan (new Plan (p, [goal2, goal1]),
			    goal2, goal1))
			{
				break first_loop;
			}

			swap (goal1.row, goal2.row);
			scope (exit)
			{
				swap (goal1.row, goal2.row);
			}

			if (try_plan (new Plan (p, [goal1, goal2]),
			    goal1, goal2))
			{
				break first_loop;
			}

			if (try_plan (new Plan (p, [goal2, goal1]),
			    goal2, goal1))
			{
				break first_loop;
			}
		}
	}

	sort !((a, b) => a.plan.score_rating > b.plan.score_rating ||
	    (a.plan.score_rating == b.plan.score_rating &&
	    a.plan.sketch_value > b.plan.sketch_value),
//	    a.plan.check_points.length < b.plan.check_points.length),
	    SwapStrategy.stable) (plans);
	stdout.writeln ("Problem ", p.name, ' ', plans.length, ' ',
	    plans.length > 0 ? plans[0].plan.score_rating : -1, ' ',
	    plans.length > 0 ? plans[$ - 1].plan.score_rating : -1);
	stdout.flush ();
	stderr.writeln ("Problem ", p.name, ' ', plans.length, ' ',
	    plans.length > 0 ? plans[0].plan.score_rating : -1, ' ',
	    plans.length > 0 ? plans[$ - 1].plan.score_rating : -1);
	stderr.flush ();

	int counter = 0;
	int [ulong] visited;
	static immutable int PRIME = 262_139;
	foreach (fat_plan; plans.drop (PLANS_TO_DROP))
	{
		if (counter >= MAX_COUNTER)
		{
			break;
		}
		auto plan = fat_plan.plan;
		if (plan.check_points.length > MAX_CHECK_POINTS)
		{
			continue;
		}

/*
		if (!(plan.goal_moves[0].to_masked_string ().toUpper () ==
		    "UNEXCEPTIONABLY" &&
//		    "DEMYTHOLOGIZERS" &&
//		    "NONQUANTIFIABLE" &&
		    plan.goal_moves[1].to_masked_string ().toUpper () ==
		    "DEMYTHOLOGIZERS"))
//		    "OXYPHENBUTAZONE"))
//		    "NONQUANTIFIABLE"))
//		    plan.goal_moves[1].to_masked_string () ==
//		    "IneXPliCabILitY"))
		{
			continue;
		}
*/

		ulong cur_hash = 0;
		foreach (goal_move; plan.goal_moves)
		{
			foreach (tile; goal_move.word)
			{
				cur_hash = cur_hash * PRIME +
				    (tile & LET_MASK);
			}
			cur_hash = cur_hash * PRIME + goal_move.row;
			cur_hash = cur_hash * PRIME + goal_move.col;
		}

		visited[cur_hash]++;
//		writeln (visited);
		if (visited[cur_hash] > MAX_SIMILAR_PLANS)
		{
/*		
			if (uniform (0, visited[cur_hash], random))
			{
				continue;
			}
*/
			continue;
		}

		stdout.writeln ("Entry: ", counter + 1);
		stdout.flush ();
		stderr.writeln ("Entry: ", counter + 1);
		stderr.flush ();

		scope (exit)
		{
			counter++;
		}
		
// /*
		if (!run_plan (t, s, m, plan, MAX_SCORE_GAP, MAX_REFINE_STEPS,
		    START_WIDTH, MAX_WIDTH, DELTA_WIDTH, MAX_DEPTH))
		{
			continue;
		}
// */

		TileCounter prev_counter;
		foreach (goal_move; plan.goal_moves)
		{
			foreach (let; goal_move.word)
			{
				prev_counter[let & LET_MASK]++;
			}
		}

		int count0;
		int count1;
		int count2;
		int count3;
		int inner_counter = 0;
		outer_loop:
		foreach (num3, pre_goal3; all_goals[0].take (MAX_CENTER_GOALS))
		{
			auto goal3 = new Goal (pre_goal3);
			goal3.row = Board.CENTER;
			count0++;

			if (goal3.count_forbidden > MAX_CENTER_FORBIDDEN)
			{
				continue;
			}
			count1++;
			
			if (start_counter[goal3.word[Board.CENTER] &
			    LET_MASK] == 0)
			{
				continue;
			}
			count2++;

			TileCounter counter3 = prev_counter;
			foreach (let; goal3.word)
			{
				counter3[let & LET_MASK]++;
			}
			if (!(total_counter >>> counter3))
//			if (!(counter3 << total_counter))
			{
				continue;
			}
			count3++;

/*
			if (goal3.word.map !(a => (a & LET_MASK) + 'A') ()
			    .array () != "FORESIGHTEDNESS")
//			    .array () != "THERMOCHEMISTRY")
//			    .array () != "OVERGENERALIZED")
//			    .array () != "OVERADVERTISING")
//			    .array () != "SUPERPHENOMENON")
			{
				continue;
			}
*/

			writeln (goal3.score_rating);
			TileCounter counter_lo;
			foreach_reverse (lo; 1..Board.CENTER + 1)
			{
				if (goal3.is_final_pos (lo))
				{
					break;
				}

				counter_lo[goal3.word[lo]]++;
				if (!(start_counter >>> counter_lo))
//				if (!(counter_lo << start_counter))
				{
					break;
				}
				int vlo = Trie.ROOT;
				foreach (pos; lo..Board.CENTER + 1)
				{
					vlo = t.contents[vlo]
					    .next (goal3.word[pos]);
					if (vlo == NA)
					{
						break;
					}
				}
				if (vlo == NA)
				{
					break;
				}

				TileCounter counter_hi = counter_lo;
				int vhi = vlo;
				foreach (hi; Board.CENTER + 1..Board.SIZE)
				{
					if (goal3.is_final_pos (hi - 1))
					{
						break;
					}

					if (!(start_counter >>> counter_hi))
//					if (!(counter_hi << start_counter))
					{
						break;
					}
					scope (exit)
					{
						counter_hi
						    [goal3.word[hi]]++;
					}

					if (vhi == NA)
					{
						break;
					}
					scope (exit)
					{
						vhi = t.contents[vhi]
						    .next (goal3.word[hi]);
					}

					if (hi - lo < MIN_FIRST_MOVE)
					{
						continue;
					}

					if (hi - lo > 1 &&
					    !t.contents[vhi].word)
					{
						continue;
					}

					writeln (goal3.word[lo..hi].map
					    !(a => to !(char)
					    ((a & LET_MASK) + 'A'))
					    .to !(string));
					auto inner_plans =
					    [new Plan (p, [fat_plan.goal1,
					    fat_plan.goal2, goal3], lo, hi),
					    new Plan (p, [fat_plan.goal1,
					    goal3, fat_plan.goal2], lo, hi),
					    new Plan (p, [goal3,
					    fat_plan.goal1, fat_plan.goal2],
					    lo, hi)];
					foreach (ref inner_plan; inner_plans)
					{
						if (inner_counter >=
						    MAX_INNER_COUNTER)
						{
							break outer_loop;
						}

						if (inner_plan
						    .score_rating == NA)
						{
							continue;
						}

						if (inner_plan.check_points
						    .length > plan.check_points
						    .length +
						    MAX_ADDED_CHECK_POINTS)
						{
							continue;
						}

						stdout.writeln ("Entry: ",
						    counter + 1, '.',
						    inner_counter + 1);
						stdout.flush ();
						stderr.writeln ("Entry: ",
						    counter + 1, '.',
						    inner_counter + 1);
						stderr.flush ();

						scope (exit)
						{
							inner_counter++;
						}

/*
						static immutable string []
						    candidates = ["1.28"];
//						    candidates = ["1.54",
//						    "1.109", "2.109",
//						    "5.12", "5.28", "5.39",
//						    "5.40", "5.75"];
						auto s_cur =
						    to !(string)
						    (counter + 1) ~ '.' ~
						    to !(string)
						    (inner_counter + 1);
						if (find (candidates, s_cur)
						    .empty)
						{
							continue;
						}
*/

						run_plan (t, s, m, inner_plan,
						    MAX_SCORE_GAP,
						    MAX_CENTER_REFINE_STEPS,
						    START_CENTER_WIDTH,
						    MAX_CENTER_WIDTH,
						    DELTA_CENTER_WIDTH,
						    MAX_CENTER_DEPTH);
					}
				}
			}
		}
		writeln (count0, ' ', count1, ' ', count2, ' ', count3);
	}
}

void improve_game (Problem p_temp, Trie t, Scoring s,
    ref GameState temp, int cur_width, int cur_depth)
{
	stderr.writeln ("improve ", cur_width, ' ', cur_depth);
	stderr.writeln (p_temp.name, ' ', temp.board.score);
	stderr.flush ();
//	stderr.writeln (p_temp);
	auto full_guide =
	    build_full_guide (p_temp, temp);
//	stderr.writeln (full_guide);
	auto reduced_guide = reduce_guide
	    (full_guide, p_temp, temp, t);
//	stderr.writeln (reduced_guide);
	stderr.flush ();

	auto plan = new Plan (p_temp,
	    reduced_guide.target_board,
	    &reduced_guide.check_board,
	    reduced_guide.moves_history
	    .filter !(x => x.word.length == Board.SIZE));
	auto p = plan.problem;
//	stderr.writeln (p);
/*
	foreach (goal_move; plan.goal_moves)
	{
		writeln (goal_move.word.map !(a => to !(char)
		    ((a & BoardCell.IS_ACTIVE) ? '*' :
		    a + 'a')).array, '!',
		    goal_move.tiles_before);
	}
*/
	auto game = new Game !(Trie) (t, s, plan);
	auto start = GameState (p);
	start.tiles.target_board = plan.target_board;
	stderr.writeln (plan);
	stderr.flush ();
	auto next = game_beam_search ([start], game, cur_width, cur_depth);
	log_progress (p, next);
}

void main (string [] args)
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
//	auto t = new Trie (read_all_lines ("data/words8.txt"), 233_691);
	auto s = global_scoring;
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

/*
	generate_all_goals (t);
	return;
*/

/*
	auto goals_relaxed = GoalBuilder.read_fat_goals
	    (read_all_lines ("data/goals.txt"), false);
	foreach (ref goal; goals_relaxed)
	{
		goal.stage = Goal.Stage.GREEDY;
		goal.stored_score_rating = goal.calc_score_rating (s);
	}

	auto goals = GoalBuilder.read_fat_goals
	    (read_all_lines ("data/goals.txt"), true);
	foreach (ref goal; goals)
	{
		goal.stage = Goal.Stage.COMBINED;
		goal.stored_score_rating = goal.calc_score_rating (s);
	}

	auto goals_center = GoalBuilder.read_fat_center_goals
	    (read_all_lines ("data/goals-center-full.txt"));
	foreach (ref goal; goals_center)
	{
		goal.row = Board.CENTER;
		goal.stage = Goal.Stage.CENTER;
		goal.stored_score_rating = goal.calc_score_rating (s);
	}
*/

	auto all_goals_0 = GoalBuilder.read_all_goals
	    (read_all_lines ("data/goals/s-0.txt"));
	auto all_goals_1 = GoalBuilder.read_all_goals
	    (read_all_lines ("data/goals/s-1.txt"));
	Goal [] [2] all_goals = [all_goals_0[0], all_goals_1[1]];
	foreach (k; 0..2)
	{
		foreach (ref goal; all_goals[k])
		{
			goal.stage = Goal.Stage.GREEDY;
			goal.stored_score_rating = goal.calc_score_rating (s);
		}
//		sort !((a, b) => a.score_rating > b.score_rating)
//		    (all_goals[k]);
//		writeln (all_goals[k][0]);
	}

	auto m = new Manager (ps);
	global_manager = m;
	GC.collect ();

	version (manager)
	{
		m.read_log ("log.txt");
		foreach (c; 0..10)
		{
			m.read_log ("log0" ~ to !(string) (c) ~ ".txt");
		}
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
		foreach (c; 0..10)
		{
			m.extract_log ("log0" ~ to !(string) (c) ~ ".txt");
		}
		foreach (c; 1..100)
		{
			m.extract_log ("log" ~ to !(string) (c) ~ ".txt");
		}
		m.close ();
		return;
	}

	version (refine)
	{
		static immutable int DEFAULT_WIDTH = 10_000;
		int cur_width = DEFAULT_WIDTH;
		int cur_depth = 0;
		int letters_todo = (1 << LET) - 1;
		args.popFront (); // path to executable
		while (!args.empty)
		{
			auto temp_str = args.front ();
			args.popFront ();
			try
			{
				int temp = to !(int) (temp_str);
				cur_width = temp;
			}
			catch (Exception)
			{
				letters_todo = 0;
				foreach (let; temp_str)
				{
					enforce ('A' <= let && let <= 'Z');
					letters_todo |= 1 << (let - 'A');
				}
			}
		}

		foreach (i; 0..LET)
		{
			if (!(letters_todo & (1 << i)))
			{
				continue;
			}

			auto p = ps.problem[i];
			auto game = new GameComplex (p, t, s);
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
			    !((GameMove a) => true)
//			    !((GameMove a) => a.count_active > 1)
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
			stderr.writeln (p_restricted);
			stderr.flush ();

			game.moves_guide = necessary_guide;
			game.problem = p_restricted;
			game.forced_lock_wildcards = true;
			stderr.writefln ("%s w=%s d=%s", p.name,
			    cur_width, cur_depth);
			stderr.flush ();
			game.play (cur_width, cur_depth,
			    GameComplex.Keep.False);
			log_progress (game);
		}
		return;
	}

	version (improve)
	{
		static immutable int DEFAULT_WIDTH = 10_000;
		int cur_width = DEFAULT_WIDTH;
		int cur_depth = 0;
		int letters_todo = (1 << LET) - 1;
		args.popFront (); // path to executable
		while (!args.empty)
		{
			auto temp_str = args.front ();
			args.popFront ();
			try
			{
				int temp = to !(int) (temp_str);
				cur_width = temp;
			}
			catch (Exception)
			{
				letters_todo = 0;
				foreach (let; temp_str)
				{
					enforce ('A' <= let && let <= 'Z');
					letters_todo |= 1 << (let - 'A');
				}
			}
		}

		foreach (i; 0..LET)
		{
			if (!(letters_todo & (1 << i)))
			{
				continue;
			}

			auto p_temp = ps.problem[i];
			auto temp = m.best["" ~ to !(char) (i + 'a')];

			improve_game (p_temp, t, s,
			    temp, cur_width, cur_depth);
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
			auto game = new GameComplex (p_first, t, s);
			game.goals = [cur_goals[0]];
			cur_goals[0].row = Board.SIZE - 1;
			game.bias = -bias;
			stderr.writefln ("%s w=%s d=%s b=%s %(%s\n    %)",
			    p.name, beam_width, beam_depth, bias,
			    game.goals);
			stderr.flush ();
			game.play (beam_width, beam_depth,
			    GameComplex.Keep.True);
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
			    cur_middle /* - 10 */, GameComplex.Keep.False,
			    true, false, true);
			log_progress (game);
		}
		while (false);

		do
		{
			auto game = new GameComplex (p_first, t, s);
			game.goals = [cur_goals[0]];
			cur_goals[0].row = 0;
			game.bias = +bias;
			stderr.writefln ("%s w=%s d=%s b=%s %(%s\n    %)",
			    p.name, beam_width, beam_depth, bias,
			    game.goals);
			stderr.flush ();
			game.play (beam_width, beam_depth,
			    GameComplex.Keep.True);
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
			    cur_middle /* - 10 */, GameComplex.Keep.False,
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
		[GameState (p)]
		    .game_beam_search (new Game !(Trie) (t, s), 10, 0)
		    .board.writeln;
		stdout.flush ();
	}
	return;
*/

/*
	foreach (i; 0..LET)
	{
		if (i != 'S' - 'A')
		{
			continue;
		}
		auto p = ps.problem[i];
		put_two_plan (t, s, p, m, all_goals);
	}
	return;
*/

// /*
	foreach (i; 0..LET)
	{
		if (i != 'Y' - 'A')
		{
			continue;
		}
		auto p = ps.problem[i];
		put_three_plan (t, s, p, m, all_goals);
	}
	return;
// */

/*
	foreach (i; 0..LET)
	{
		auto p = ps.problem[i];
		auto goal1 = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto goal2 = new Goal ("SesQuIcEnTeNarY",
		    Board.SIZE - 1, 0, false);
		auto plan = new Plan (p, [goal1, goal2]);
		writeln (plan);
		auto game = new Game !(Trie) (t, s, plan);
		auto cur = GameState (plan.problem);
		cur.tiles.target_board = plan.target_board;
		auto next = game_beam_search ([cur], game, 100, 0);
		log_progress (p, next);
	}
	return;
*/

/*
	foreach (i; 0..LET)
	{
		auto p = ps.problem[i];
//		auto goal = new Goal ("OXYPhenButaZonE", 0, 0, false);
		auto goal = new Goal ("SesQuIcEnTeNarY",
		    Board.SIZE - 1, 0, false);
		auto plan = new Plan (p, [goal]);
		writeln (plan);
		auto game = new Game !(Trie) (t, s, plan);
		auto cur = GameState (plan.problem);
		cur.tiles.target_board = plan.target_board;
		auto next = game_beam_search ([cur], game, 100, 0);
		log_progress (p, next);
	}
	return;
*/

/*
	foreach (i; 0..1)
	{
		auto p = ps.problem[i];
		auto game = new GameComplex (p, t, s);
		game.play (10, 0, GameComplex.Keep.False);
		writeln (game.best);
	}
	return;
*/

/*
	foreach (i; 0..LET)
	{
		if (i != 'S' - 'A')
		{
			continue;
		}
		auto p = ps.problem[i];

//		put_two (250, 0, 4, 8, p, t, s,
//		    goals_relaxed ~ goals, goals, [], null);
//		put_two (3200, 0, 2, 4, p, t, s,
//		    goals_relaxed ~ goals, goals, [], null);
		put_two (25000, 0, 1, 2, p, t, s,
		    goals_relaxed ~ goals, goals, [], null);
 
*/ /*
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
				auto game = new GameComplex (p_first, t, s);
				game.goals = [cur_goals[0]];
				game.bias = 0;
				stderr.writefln ("%s w=%s d=%s b=%s " ~
				    "%(%s\n    %)", p.name, beam_width,
				    beam_depth, game.bias, game.goals);
				stderr.flush ();
				game.play (beam_width, beam_depth,
				    GameComplex.Keep.False);
				log_progress (game);
				middle_state = game.best;
			}

			if (true)
			{
				auto middle_complete_guide = GameMove.invert
				    (middle_state.closest_move);

				auto game = new GameComplex (p, t, s);
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
*/ /*
	}
*/
}
