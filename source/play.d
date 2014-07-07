module play;

import std.algorithm;
import std.array;
import std.conv;
import std.stdio;

import board;
import game_move;
import game_state;
import general;
import problem;
import scoring;
import tile_bag;
import trie;

enum RackUsage: byte {Active, Passive, Ignore};

struct Play (DictClass, RackUsage rack_usage = RackUsage.Active)
{
	DictClass stored_dict;
	Scoring stored_scoring;
	Board * stored_check_board;

	GameState * stored_cur;
	
	GameMove stored_cur_move;

	static if (rack_usage != RackUsage.Active)
	{
		GameMove pending_move;
	}

	void move_start (ref GameState cur,
	    int delegate (ref GameState) process)
	{
		DictClass dict = stored_dict;
		Scoring scoring = stored_scoring;
		Board * check_board = stored_check_board;

		byte row = byte.max;
		byte col = byte.max;
		byte connections = 0;
		byte active_tiles = 0;
		int vert_score = 0;
		int main_score = 0;
		int score_mult = 1;
		int vt = DictClass.ROOT;

		GameMove cur_move = stored_cur_move;

		bool check_tile ()
		{
			if (check_board is null)
			{
				return true;
			}
			if (check_board.is_flipped == cur.board.is_flipped)
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

		void consider ()
		{
			version (debug_play)
			{
				writeln ("consider ", row, ' ', col);
			}
			int add_score = scoring.calculate (vert_score,
			    main_score, score_mult, active_tiles);
			cur.board.score += add_score;
			cur.closest_move = new GameMove (cur_move);
			cur.closest_move.score = add_score;
			cur.closest_move.word = cur.closest_move.word.dup;
			auto tiles_saved = cur.tiles;
			cur.tiles.rack.normalize ();
			cur.tiles.fill_rack ();
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
			process (cur);
		}

		int check_vertical ()
		{
			version (debug_play)
			{
				writeln ("check_vertical ", row, ' ', col);
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
			return score * mult;
		}

		void step_recur () ()
		{ // templated to recurse into move_recur
			version (debug_play)
			{
				writeln ("step_recur ", row, ' ', col);
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
				writeln ("move_recur ", row, ' ', col);
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
					auto cur_tile_number =
					    cur.tiles.target_board[row][col];
					if (cur_tile_number != NA)
					{
						if (cur_tile_number < cur.tiles.cursor)
						{
							cur.board[row][col] =
							    (cur.tiles[cur_tile_number] &
							    LET_MASK) |
							    (1 << BoardCell.ACTIVE_SHIFT);
							cur.tiles.dec_restricted
							    (cur.board[row][col]);
							scope (exit)
							{
								cur.tiles.inc_restricted
								    (cur.board[row][col]);
							}
							step_recur ();
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
	
					if (c.num != 0)
					{
						cur.tiles.dec (c);
						scope (exit)
						{
							cur.tiles.inc (c);
						}

						if (!c.is_wildcard)
						{
							cur.board[row][col] =
							    c.letter |
							    (1 << BoardCell
							    .ACTIVE_SHIFT);
							step_recur ();
							continue;
						}

						foreach (ubyte letter; 0..LET)
						{
							cur.board[row][col] =
							    letter |
							    (1 << BoardCell
							    .WILDCARD_SHIFT) |
							    (1 << BoardCell
							    .ACTIVE_SHIFT);
							step_recur ();
						}
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
				writeln ("move_horizontal");
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
				writeln ("perform_move");
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
				if (cur_move.tiles_before > cur.board.total)
				{
					return;
				}
			}

			if (col > 0 && !cur.board[row][col - 1].empty)
			{
				return;
			}
			if (col + 1 < Board.SIZE &&
			    !cur.board[row][col + 1].empty)
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

			static if (rack_usage == RackUsage.Passive)
			{
				if (has_passive_empty)
				{
					return;
				}
			}

			if (has_active_filled)
			{
				if (!has_empty)
				{
					process (cur);
				}
				return;
			}

			static if (rack_usage == RackUsage.Ignore)
			{
				byte saved_total = Rack.IGNORED;
				swap (cur.tiles.rack.total, saved_total);
				connections++;
				scope (exit)
				{
					swap (cur.tiles.rack.total,
					    saved_total);
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
					cur.board[row][col + pos] = move_tile |
					    (1 << BoardCell.ACTIVE_SHIFT);
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
			bool to_flip = (cur.board.is_flipped ==
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

	this (DictClass new_dict, Scoring new_scoring,
	    Board * new_check_board = null)
	{
		stored_dict = new_dict;
		stored_scoring = new_scoring;
		stored_check_board = new_check_board;
		
		stored_cur_move = new GameMove ();
	}
}

ref GameState play_move (DictClass, RackUsage rack_usage)
    (DictClass dict, Scoring scoring, ref GameState cur, GameMove cur_move)
{
	static assert (rack_usage != RackUsage.Active);
	auto play = Play !(DictClass, rack_usage) (dict, scoring);
	GameState temp;
	temp.board.value = NA;
	foreach (ref next; play (cur, cur_move))
	{
		temp = next;
	}
	cur = temp;
	return cur;
}

unittest
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
	auto s = new Scoring ();

	void test_1 ()
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
	}

	void test_2 ()
	{
		auto play = Play !(Trie, RackUsage.Passive) (t, s);
		auto cur = GameState (Problem ("?:", "abcDEFG"));
		auto cur_move = new GameMove ();

		cur_move.initialize (cur);
		cur_move.start_at (Board.CENTER, Board.CENTER);
		cur_move.word = "cab"
		    .map !(c => BoardCell (to !(byte) ((c - 'a') |
		    (1 << BoardCell.ACTIVE_SHIFT)))) ()
		    .array ();
		int num = 0;
		foreach (ref next; play (cur, cur_move))
		{
			assert (next.board.score > 0);
			num++;
		}
		assert (num == 1);
	}

	void test_3 ()
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

	void test_4 ()
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

		cur_move.initialize (cur);
		cur_move.start_at (0, 0);
		cur_move.is_flipped = false;
		cur_move.word = "SESQUICENTENARY"
		    .map !(c => BoardCell (to !(byte) (c - 'A'))) ()
		    .array ();
		play_move !(Trie, RackUsage.Ignore) (t, s, cur, cur_move);
		assert (cur.board.value == NA);
	}

	test_1 ();
	test_2 ();
	test_3 ();
	test_4 ();
}
