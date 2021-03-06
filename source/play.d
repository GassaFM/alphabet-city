module play;

import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.stdio;

import board;
import game_move;
import game_state;
import general;
import problem;
import scoring;
import tile_bag;
import trie;

enum RackUsage: byte
    {Active, // use tiles.rack to produce moves
    Passive, // use cur_move to produce moves
    Fake, // invalidate tiles.rack but watch connectivity and activity
    Ignore}; // allow disconnected and passive, check only the resulting board

// This boils down to the following:                          A P F I
// (1) use tiles.rack (+) or cur_move (-) to generate moves   + - - -
// (2) account in tiles.rack (+) or invalidate it (-)         + + - -
// (3) allow present but active cells (+) or not (-)          - - - +
// (4) allow missing but passive cells (+) or not (-)         - - - +
// (5) allow fully present moves (+) or not (-)               - - - +
// (6) allow disconnected moves (+) or not (-)                - - - +
// TODO 1: derive these booleans as enums or static immutable bools
// TODO 2: unittests on that
// TODO 3: correctly account for bingos when counting active tiles

struct Play (DictClass, RackUsage rack_usage = RackUsage.Active)
{
	const DictClass stored_dict;
	const Scoring stored_scoring;
	const Board * stored_check_board;

	GameState * stored_cur;
	
	GameMove stored_cur_move;

	static immutable bool allow_targets_earlier = true;

	static if (rack_usage != RackUsage.Active)
	{
		GameMove pending_move;
	}

	void move_start (ref GameState cur,
	    int delegate (ref GameState) process)
	{
		const DictClass dict = stored_dict;
		const Scoring scoring = stored_scoring;
		const Board * check_board = stored_check_board;

		byte row = byte.max;
		byte col = byte.max;
		byte connections = 0;
		byte active_tiles = 0;
		int vert_score = 0;
		int main_score = 0;
		int score_mult = 1;
		int vt = DictClass.ROOT;

		GameMove cur_move = stored_cur_move;

		bool check_tile () ()
		{
			if (check_board is null)
			{
				return true;
			}
			if ((*check_board).is_flipped == cur.board.is_flipped)
			{
				return (*check_board)[row][col].empty ||
				    ((*check_board)[row][col].letter ==
				    cur.board[row][col].letter);
			}
			else
			{
				return (*check_board)[col][row].empty ||
				    ((*check_board)[col][row].letter ==
				    cur.board[row][col].letter);
			}
		}

		void consider () ()
		{
			version (debug_play)
			{
				writeln (">consider ", row, ' ', col);
				scope (exit)
				{ 
					writeln ("<consider ", row, ' ', col);
				}
			}
			int add_score = scoring.calculate (vert_score,
			    main_score, score_mult, active_tiles);
			cur.board.score += add_score;
			cur.closest_move = new GameMove (cur_move);
			cur.closest_move.score = add_score;
			cur.closest_move.word = cur.closest_move.word.dup;
			auto tiles_saved = cur.tiles;
			cur.tiles.rack.normalize ();
			cur.fill_rack ();
			auto hash_saved = cur.board.contents_hash[0];
			cur_move.add_hash (cur.board);
			cur.xor_active ();
			scope (exit)
			{
				cur.xor_active ();
				cur.board.contents_hash[0] = hash_saved;
				cur.tiles = tiles_saved;
				cur.closest_move = cur_move.chained_move;
				cur.board.score -= add_score;
			}
			int temp_result = process (cur);
		}

		int check_vertical () ()
		{
			version (debug_play)
			{
				writeln (">check_vertical ", row, ' ', col);
				scope (exit)
				{
					writeln ("<check_vertical ",
					    row, ' ', col);
				}
			}
			if (!cur.board[row][col].active)
			{
				return 0;
			}

			int cur_row = row;
			while (cur_row > 0 &&
			    !cur.board[cur_row - 1][col].empty)
			{
				cur_row--;
			}

			if (cur_row == row &&
			    (cur_row == Board.SIZE - 1 ||
			    cur.board[cur_row + 1][col].empty))
			{
				return 0;
			}

			int score = 0;
			int mult = 1;
			int v = DictClass.ROOT;
			do
			{
				v = dict.contents[v].next
				    (cur.board[cur_row][col].letter);
				scoring.account (score, mult,
				    cur.board[cur_row][col], cur_row, col);
				if (v == NA)
				{
					return NA;
				}
				cur_row++;
			}
			while (cur_row < Board.SIZE &&
			    !cur.board[cur_row][col].empty);

			if (!dict.contents[v].word)
			{
				return NA;
			}

			// TODO: add check with check_board without score here
			return score * mult;
		}

		void step_recur () ()
		{ // templated to recurse into move_recur
			version (debug_play)
			{
				writeln (">step_recur ", row, ' ', col);
				scope (exit)
				{
					writeln ("<step_recur ",
					    row, ' ', col);
				}
			}
			assert (!cur.board[row][col].empty);

			if (!check_tile ())
			{
				return;
			}

			int vt_saved = vt;
			scope (exit)
			{
				vt = vt_saved;
			}
			vt = dict.contents[vt].next (cur.board[row][col]);
			if (vt == NA)
			{
				return;
			}

			int vert_add = check_vertical ();
			if (vert_add == NA)
			{
				return;
			}

			int main_score_saved = main_score;
			int score_mult_saved = score_mult;
			connections += (vert_add > 0) ||
			    (row == Board.CENTER &&
			    col == Board.CENTER);
			vert_score += vert_add;
			cur_move.word ~= cur.board[row][col];
			scope (exit)
			{
				main_score = main_score_saved;
				score_mult = score_mult_saved;
				connections -= (vert_add > 0) ||
				    (row == Board.CENTER &&
				    col == Board.CENTER);
				vert_score -= vert_add;
				cur_move.word.length--;
				cur_move.word.assumeSafeAppend ();
			}
			scoring.account (main_score, score_mult,
			    cur.board[row][col], row, col);

			if (col + 1 == Board.SIZE ||
			    cur.board[row][col + 1].empty)
			{
				if (dict.contents[vt].word &&
				    connections &&
				    (active_tiles >= (1 +
				    (cur.board.is_flipped && vert_score))))
				{ // 1-letter h+v move ~always not flipped
					consider ();
				}
			}
			if (col + 1 < Board.SIZE)
			{
				col++;
				scope (exit)
				{
					col--;
				}
				move_recur ();
			}
		}

		void move_recur () ()
		{
			version (debug_play)
			{
				writeln (">move_recur ", row, ' ', col);
				scope (exit)
				{
					writeln ("<move_recur ",
					    row, ' ', col);
				}
			}
			static if (rack_usage == RackUsage.Active)
			{
				if (!cur.board[row][col].empty)
				{
					connections++;
					scope (exit)
					{
						connections--;
					}
					step_recur ();
					return;
				}

				cur.board.total++;
				active_tiles++;
				scope (exit)
				{
					cur.board.total--;
					active_tiles--;
					cur.board[row][col] = BoardCell.NONE;
				}

				if (cur.tiles.target_board !is null)
				{
					int cur_tile_number;
					if (!cur.board.is_flipped)
					{
						cur_tile_number =
						    cur.tiles.target_board
						    .tile_number[row][col];
					}
					else
					{
						cur_tile_number =
						    cur.tiles.target_board
						    .tile_number[col][row];
					}
					if (cur_tile_number >= 0)
					{ // NA = free, other_negative = guided
						auto target_tile =
						    cur.tiles[cur_tile_number];
						BoardCell tile_to_put;
						if ((target_tile & LET_MASK) == LET)
						{
							if (!cur.board.is_flipped)
							{
								assert (check_board !is null &&
								    !(*check_board)
								    [row][col].empty &&
								    (*check_board)[row][col]
								    .wildcard);
								tile_to_put =
								    (*check_board)[row][col];
							}
							else
							{
								assert (check_board !is null &&
								    !(*check_board)
								    [col][row].empty &&
								    (*check_board)[col][row]
								    .wildcard);
								tile_to_put =
								    (*check_board)[col][row];

							}
						}
						else
						{
							tile_to_put =
							    target_tile &
							    LET_MASK;
						}
						tile_to_put |= BoardCell.IS_ACTIVE;

						if (cur_tile_number < cur.tiles.cursor)
						{
							if ((target_tile & LET_MASK) == LET)
							{
								cur.board[row][col] =
								    tile_to_put;
							}
							else
							{
								cur.board[row][col] =
								    tile_to_put;
							}
							cur.tiles.dec_restricted
							    (cur.board[row][col]);
							scope (exit)
							{
								cur.tiles.inc_restricted
								    (cur.board[row][col]);
							}
							step_recur ();
							return;
						}
						else if (allow_targets_earlier)
						{
							if ((target_tile &
							    LET_MASK) == LET)
							{ // wildcard target
								foreach (ref c;
								    cur.tiles.rack.contents)
								{
									if (c.empty)
									{
										break;
									}

									if (c.num == 0)
									{
										continue;
									}

									if (c.is_wildcard)
									{
										cur.tiles.dec (c);
										scope (exit)
										{
											cur.tiles.inc (c);
										}

										cur.board[row][col] =
										    tile_to_put;
										step_recur ();
										break;
									}
								}

								return;
							}

							foreach (ref c;
							    cur.tiles.rack.contents)
							{
								if (c.empty)
								{
									break;
								}

								if (c.num == 0)
								{
									continue;
								}

								if (!c.is_wildcard &&
								    c.letter ==
								    (target_tile &
								    LET_MASK))
								{
									cur.tiles.dec (c);
									scope (exit)
									{
										cur.tiles.inc (c);
									}

									cur.board[row][col] =
									    tile_to_put;
									step_recur ();
									break;
								}
							}
						}
						return;
					}
				}

				foreach (ref c; cur.tiles.rack.contents)
				{
					if (c.empty)
					{
						break;
					}

					if (c.num == 0)
					{
						continue;
					}

					cur.tiles.dec (c);
					scope (exit)
					{
						cur.tiles.inc (c);
					}

					if (!c.is_wildcard)
					{
						cur.board[row][col] =
						    c.letter |
						    BoardCell.IS_ACTIVE;
						step_recur ();
						continue;
					}

					foreach (ubyte letter; 0..LET)
					{
						cur.board[row][col] =
						    letter |
						    BoardCell.IS_WILDCARD |
						    BoardCell.IS_ACTIVE;
						step_recur ();
					}
				}
			}
			else
			{
				if (!cur.board[row][col].empty)
				{
					step_recur ();
					return;
				}
			}
		}

		void move_horizontal () ()
		{
			version (debug_play)
			{
				writeln (">move_horizontal");
				scope (exit)
				{
					writeln ("<move_horizontal");
				}
			}
			static if (rack_usage != RackUsage.Active)
			{
				static assert (false);
			}

			cur_move.initialize (cur);
			for (row = 0; row < Board.SIZE; row++)
			{
				for (col = 0; col < Board.SIZE; col++)
				{
					if (cur.board.suggest_start_move
					    (row, col,
					    cur.tiles.rack.usable_total))
					{
						cur_move.start_at (row, col);
						move_recur ();
					}
				}
			}
		}

		void perform_move () ()
		{
			version (debug_play)
			{
				writeln (">perform_move");
				scope (exit)
				{
					writeln ("<perform_move");
				}
			}
			static if (rack_usage == RackUsage.Active)
			{
				static assert (false);
			}
			static if (rack_usage == RackUsage.Passive)
			{
/*
				int tiles_cursor = cur.tiles.cursor;
				int move_cursor = min (TOTAL_TILES,
				    cur_move.tiles_before + Rack.MAX_SIZE);
				if (move_cursor > tiles_cursor) // may be safer
*/
				if (pending_move.tiles_before >
				    cur.board.total)
				{
					return;
				}
			}

			if (col > 0 && !cur.board[row][col - 1].empty)
			{
				return;
			}
			if (col + pending_move.word.length < Board.SIZE &&
			    !cur.board[row][col +
			    pending_move.word.length].empty)
			{
				return;
			}

			bool has_active_filled = false;
			bool has_passive_empty = false;
			bool has_filled = false;
			bool has_empty = false;
			foreach (pos, move_tile; pending_move.word)
			{
				auto board_tile = cur.board[row][col + pos];
				if (board_tile.empty)
				{
					has_empty = true;
					if (!move_tile.active)
					{
						has_passive_empty = true;
					}
				}
				else if (board_tile.letter != move_tile.letter)
				{
					return;
				}
				else
				{
					has_filled = true;
					if (move_tile.active)
					{
						has_active_filled = true;
					}
				}
			}

			static if (rack_usage == RackUsage.Passive ||
			    rack_usage == RackUsage.Fake)
			{
				if (has_passive_empty)
				{
					return;
				}
			}

			if (has_active_filled)
			{
				static if (rack_usage == RackUsage.Ignore)
				{
					if (!has_empty)
					{
						process (cur);
					}
				}
				return;
			}

			static if (rack_usage == RackUsage.Fake ||
			    rack_usage == RackUsage.Ignore)
			{
				byte saved_total = Rack.IGNORED;
				swap (cur.tiles.rack.total, saved_total);
				byte saved_active = Rack.IGNORED;
				swap (cur.tiles.rack.active, saved_active);
				scope (exit)
				{
					swap (cur.tiles.rack.total,
					    saved_total);
					swap (cur.tiles.rack.active,
					    saved_active);
				}
			}

			static if (rack_usage == RackUsage.Ignore)
			{
				active_tiles += 2;
				connections++;
				scope (exit)
				{
					active_tiles -= 2;
					connections--;
				}
			}

			if (has_filled)
			{
				connections++;
			}
			scope (exit)
			{
				if (has_filled)
				{
					connections--;
				}
			}

			foreach (pos, move_tile; pending_move.word)
			{
				if (cur.board[row][col + pos].empty)
				{
					cur.board.total++;
					cur.board[row][col + pos] = move_tile |
					    BoardCell.IS_ACTIVE;
					static if (rack_usage ==
					    RackUsage.Passive)
					{
						cur.tiles.dec_restricted
						    (move_tile);
					}
				}
				if (move_tile.active)
				{
					active_tiles++;
				}
			}
			bool no_active_tiles = (active_tiles == 0);
			if (no_active_tiles)
			{
				active_tiles++;
			}
			scope (exit)
			{
				foreach (pos, move_tile; pending_move.word)
				{
					if (cur.board[row][col + pos].active)
					{
						cur.board.total--;
						cur.board[row][col + pos] =
						    BoardCell.NONE;
						static if (rack_usage ==
						    RackUsage.Passive)
						{
							cur.tiles
							    .inc_restricted
							    (move_tile);
						}
					}
					if (move_tile.active)
					{
						active_tiles--;
					}
				}
				if (no_active_tiles)
				{
					active_tiles--;
				}
			}

			move_recur ();
		}

		static if (rack_usage == RackUsage.Active)
		{
			move_horizontal ();
			cur.board.flip ();
			move_horizontal ();
			cur.board.flip ();
		}
		else
		{
			bool to_flip = (cur.board.is_flipped !=
			    pending_move.is_flipped);
			if (to_flip)
			{
				cur.board.flip ();
			}
			scope (exit)
			{
				if (to_flip)
				{
					cur.board.flip ();
				}
			}
			row = pending_move.row;
			col = pending_move.col;
			cur_move.initialize (cur);
			cur_move.start_at (row, col);
			perform_move ();
		}
	}

	static if (rack_usage == RackUsage.Active)
	{
		ref typeof (this) opCall (ref GameState new_cur)
		{
			stored_cur = &new_cur;
			return this;
		}
	}
	else
	{
		ref typeof (this) opCall (ref GameState new_cur,
		    GameMove new_pending_move)
		{
			stored_cur = &new_cur;
			pending_move = new_pending_move;
			return this;
		}
	}

	int opApply (int delegate (ref GameState) new_process)
	{
		move_start (*stored_cur, new_process);

		return 0;
	}

	this (const DictClass new_dict, const Scoring new_scoring,
	    const Board * new_check_board = null)
	{
		stored_dict = new_dict;
		stored_scoring = new_scoring;
		stored_check_board = new_check_board;
		
		stored_cur_move = new GameMove ();
	}
}

ref GameState play_move (DictClass, RackUsage rack_usage)
    (const DictClass dict, const Scoring scoring,
    ref GameState cur, GameMove cur_move)
{
	static assert (rack_usage != RackUsage.Active);
	auto play = Play !(DictClass, rack_usage) (dict, scoring);
	GameState temp;
	temp.board.score = NA;
	foreach (ref next; play (cur, cur_move))
	{
		temp = next;
	}
	cur = temp;
	return cur;
}

ref GameState play_moves_sequence (DictClass, RackUsage rack_usage,
    GameMoveRange)
    (const DictClass dict, const Scoring scoring,
    ref GameState cur, GameMoveRange cur_moves_sequence)
    if (isInputRange !(GameMoveRange) &&
    is (Unqual !(ElementType !(GameMoveRange)) == GameMove))
{
	static assert (rack_usage != RackUsage.Active);
	auto play = Play !(DictClass, rack_usage) (dict, scoring);
	foreach (cur_move; cur_moves_sequence)
	{
		GameState temp;
		temp.board.score = NA;
		foreach (ref next; play (cur, cur_move))
		{
			temp = next;
		}
		cur = temp;
		if (cur.board.score == NA)
		{
			return cur;
		}
	}
	return cur;
}

struct CompoundPlay (DictClass)
{
	const DictClass stored_dict;
	const Scoring stored_scoring;
	const Board * stored_check_board;

	GameState * stored_cur;

	GameMove [] pending_moves;

	ref typeof (this) opCall (ref GameState new_cur,
	    GameMove [] new_pending_moves)
	{
		stored_cur = &new_cur;
		pending_moves = new_pending_moves;
		return this;
	}

	int opApply (int delegate (ref GameState) new_process)
	{
		Play !(DictClass) (stored_dict, stored_scoring,
		    stored_check_board).opCall (*stored_cur)
		    .opApply (new_process);

		foreach (pending_move; pending_moves)
		{
			Play !(DictClass, RackUsage.Passive)
			    (stored_dict, stored_scoring, stored_check_board)
			    .opCall (*stored_cur, pending_move)
			    .opApply (new_process);
		}

		return 0;
	}

	this (const DictClass new_dict, const Scoring new_scoring,
	    const Board * new_check_board = null)
	{
		stored_dict = new_dict;
		stored_scoring = new_scoring;
		stored_check_board = new_check_board;
	}
}

unittest
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
	auto s = new Scoring ();

	void test_play_active ()
	{
		auto play = Play !(Trie) (t, s);
		auto cur = GameState (Problem ("?:", "ABCDEFG"));

		int num = 0;
		foreach (ref next; play (cur))
		{
			assert (next.board.score > 0);
			num++;
		}
		assert (num > 0);
		assert (num == 320);
	}

	void test_play_passive ()
	{
		auto play = Play !(Trie, RackUsage.Passive) (t, s);
		auto cur = GameState (Problem ("?:", "abcDEFG"));
		auto cur_move = new GameMove ();

		cur_move.initialize (cur);
		cur_move.start_at (Board.CENTER, Board.CENTER);
		cur_move.word = "cab"
		    .map !(c => BoardCell (to !(byte) ((c - 'a') |
		    BoardCell.IS_ACTIVE))) ().array ();
		int num = 0;
		foreach (ref next; play (cur, cur_move))
		{
			assert (next.board.score > 0);
			assert (next.board.score == 14);
			num++;
		}
		assert (num == 1);
	}

	void test_play_fake ()
	{
		auto play = Play !(Trie, RackUsage.Fake) (t, s);
		auto cur = GameState (Problem ("?:", "ABCDEFG"));
		auto cur_move = new GameMove ();
		GameState temp;
		int num;

		// connected by center cell
		cur_move.initialize (cur);
		cur_move.start_at (Board.CENTER, Board.CENTER);
		cur_move.is_flipped = false;
		cur_move.word = "BAKE"
		    .map !(c => BoardCell (to !(byte)
		    (c - 'A' + BoardCell.IS_ACTIVE))) ().array ();
		num = 0;
		foreach (ref next; play (cur, cur_move))
		{
			temp = next;
			assert (next.board.score > 1);
			assert (next.board.score == 20);
			num++;
		}
		assert (num == 1);
		cur = temp;

		// connected by passive cell
		cur_move.initialize (cur);
		cur_move.start_at (Board.CENTER + 3, Board.CENTER - 1);
		cur_move.is_flipped = true;
		cur_move.word = "BED"
		    .map !(c => BoardCell (to !(byte) (c - 'A' +
		    (c == 'E' ? 0 : BoardCell.IS_ACTIVE)))) ().array ();
		num = 0;
		foreach (ref next; play (cur, cur_move))
		{
			temp = next;
			assert (next.board.score > 20);
			assert (next.board.score == 26);
			num++;
		}
		assert (num == 1);
		cur = temp;

		// not connected
		cur_move.initialize (cur);
		cur_move.start_at (0, 1);
		cur_move.is_flipped = false;
		cur_move.word = "SWAMP"
		    .map !(c => BoardCell (to !(byte)
		    (c - 'A' + BoardCell.IS_ACTIVE))) ().array ();
		foreach (ref next; play (cur, cur_move))
		{
			assert (false);
		}

		// not active
		cur_move.initialize (cur);
		cur_move.start_at (Board.CENTER, Board.CENTER);
		cur_move.is_flipped = true;
		cur_move.word = "BIPOLAR"
		    .map !(c => BoardCell (to !(byte)
		    (c - 'A'))) ().array ();
		foreach (ref next; play (cur, cur_move))
		{
			assert (false);
		}
	}

	void test_play_ignore ()
	{
		auto play = Play !(Trie, RackUsage.Ignore) (t, s);
		auto cur = GameState (Problem ("?:", "ABCDEFG"));
		auto cur_move = new GameMove ();

		cur_move.initialize (cur);
		cur_move.start_at (0, 0);
		cur_move.is_flipped = true;
		cur_move.word = "OXYPHENBUTAZONE"
		    .map !(c => BoardCell (to !(byte) (c - 'A'))) ()
		    .array ();
		int num = 0;
		GameState temp;
		foreach (ref next; play (cur, cur_move))
		{
			temp = next;
			assert (next.board.score > 1400);
			assert (next.board.score == 1458);
			num++;
		}
		assert (num == 1);

		cur = temp;
		cur_move.initialize (cur);
		cur_move.start_at (0, 0);
		cur_move.is_flipped = false;
		cur_move.word = "SESQUICENTENARY"
		    .map !(c => BoardCell (to !(byte) (c - 'A'))) ()
		    .array ();
		foreach (ref next; play (cur, cur_move))
		{
			assert (false);
		}
	}

	void test_play_move ()
	{
		auto cur = GameState (Problem ("?:", "ABCDEFG"));
		auto cur_move = new GameMove ();

		cur_move.initialize (cur);
		cur_move.start_at (0, 0);
		cur_move.is_flipped = true;
		cur_move.word = "OXYPHENBUTAZONE"
		    .map !(c => BoardCell (to !(byte) (c - 'A'))) ()
		    .array ();
		play_move !(Trie, RackUsage.Ignore) (t, s, cur, cur_move);
		assert (cur.board.score > 1400);
		assert (cur.board.score == 1458);

		cur_move.initialize (cur);
		cur_move.start_at (0, 0);
		cur_move.is_flipped = false;
		cur_move.word = "SESQUICENTENARY"
		    .map !(c => BoardCell (to !(byte) (c - 'A'))) ()
		    .array ();
		play_move !(Trie, RackUsage.Ignore) (t, s, cur, cur_move);
		assert (cur.board.score == NA);
	}

	void test_play_moves_sequence ()
	{
		auto cur = GameState (Problem ("?:", "ABCDEFG"));
		GameState temp;
		GameMove [] cur_moves_sequence;

		auto move1 = new GameMove ();
		move1.initialize (cur);
		move1.start_at (Board.CENTER, Board.CENTER);
		move1.is_flipped = false;
		move1.word = "BAKE"
		    .map !(c => BoardCell (to !(byte)
		    (c - 'A' + BoardCell.IS_ACTIVE))) ().array ();

		auto move2 = new GameMove ();
		move2.initialize (cur);
		move2.start_at (Board.CENTER + 3, Board.CENTER - 1);
		move2.is_flipped = true;
		move2.word = "BED"
		    .map !(c => BoardCell (to !(byte) (c - 'A' +
		    (c == 'E' ? 0 : BoardCell.IS_ACTIVE)))) ().array ();

		// not connected
		auto move3 = new GameMove ();
		move3.initialize (cur);
		move3.start_at (0, 1);
		move3.is_flipped = false;
		move3.word = "SWAMP"
		    .map !(c => BoardCell (to !(byte)
		    (c - 'A' + BoardCell.IS_ACTIVE))) ().array ();

		// not active
		auto move4 = new GameMove ();
		move4.initialize (cur);
		move4.start_at (Board.CENTER, Board.CENTER);
		move4.is_flipped = true;
		move4.word = "BIPOLAR"
		    .map !(c => BoardCell (to !(byte)
		    (c - 'A'))) ().array ();

		cur_moves_sequence = [move1, move2];
		play_moves_sequence !(Trie, RackUsage.Fake)
		    (t, s, cur, cur_moves_sequence);
		assert (cur.board.score > 20);
		assert (cur.board.score == 26);
		
		cur_moves_sequence = [move1, move2];
		temp = cur;
		play_moves_sequence !(Trie, RackUsage.Fake)
		    (t, s, temp, cur_moves_sequence);
		assert (temp.board.score == NA);

		cur_moves_sequence = [move3];
		temp = cur;
		play_moves_sequence !(Trie, RackUsage.Fake)
		    (t, s, temp, cur_moves_sequence);
		assert (temp.board.score == NA);

		cur_moves_sequence = [move4];
		temp = cur;
		play_moves_sequence !(Trie, RackUsage.Fake)
		    (t, s, temp, cur_moves_sequence);
		assert (temp.board.score == NA);
	}

	void test_check_vertical_on_ignore ()
	{
		auto cur = GameState (Problem ("?:", "ABCDEFG"));
		auto cur_move = new GameMove ();

		cur_move.initialize (cur);
		cur_move.start_at (0, 0);
		cur_move.is_flipped = true;
		cur_move.word = "OXYPHENBUTAZONE"
		    .map !(c => BoardCell (to !(byte) (c - 'A'))) ()
		    .array ();
		play_move !(Trie, RackUsage.Ignore) (t, s, cur, cur_move);
		assert (cur.board.score > 1400);
		assert (cur.board.score == 1458);

		cur_move.initialize (cur);
		cur_move.start_at (1, 0);
		cur_move.is_flipped = false;
		cur_move.word = "SESQUICENTENARY"
		    .map !(c => BoardCell (to !(byte) (c - 'A'))) ()
		    .array ();
		play_move !(Trie, RackUsage.Ignore) (t, s, cur, cur_move);
		assert (cur.board.score == NA);
	}

	void test_compound_play ()
	{
		auto play1 = Play !(Trie) (t, s);
		auto play2 = CompoundPlay !(Trie) (t, s);
		auto cur = GameState (Problem ("?:", "abcDEFG"));
		auto cur_move = new GameMove ();

		cur_move.initialize (cur);
		cur_move.start_at (Board.CENTER, Board.CENTER);
		cur_move.word = "cab"
		    .map !(c => BoardCell (to !(byte) ((c - 'a') |
		    BoardCell.IS_ACTIVE))) ().array ();

		int num1 = 0;
		foreach (ref next; play1 (cur))
		{
			assert (next.board.score > 0);
			num1++;
		}
		assert (num1 > 0);
		assert (num1 == 24);

		int num2 = 0;
		foreach (ref next; play2 (cur, [cur_move]))
		{
			assert (next.board.score > 0);
			num2++;
		}
		assert (num2 == num1 + 1);
	}

	test_play_active ();
	test_play_passive ();
	test_play_fake ();
	test_play_ignore ();
	test_play_move ();
	test_check_vertical_on_ignore ();
	test_compound_play ();
}
