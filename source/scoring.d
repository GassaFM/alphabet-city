module scoring;

import std.conv;
import std.exception;
import std.stdio;
import std.string;

import board;
import general;
import tile_bag;

class Scoring
{
	enum Bonus: byte {NO, DW, TW, DL, TL, SIZE};
	immutable static string [Bonus.SIZE] BONUS_NAME =
	    ["--", "DW", "TW", "DL", "TL"];

	Bonus [Board.SIZE] [Board.SIZE] board_bonus;
	int [LET + 1] tile_value;
	int bingo;

	void load_board_bonus (const string file_name)
	{
		string [] line_list = read_all_lines (file_name);
		enforce (line_list.length == Board.SIZE);
		foreach (i, line; line_list)
		{
			auto cur = line.split ();
			enforce (cur.length == Board.SIZE);
			foreach (j, word; cur)
			{
				bool found = false;
				foreach (b; 0..Bonus.SIZE)
				{
					if (word == BONUS_NAME[b])
					{
						board_bonus[i][j] =
						    cast (Bonus) (b);
// BUG with ldc 0.12.1:
//						    to !(Bonus) (b);
						found = true;
						break;
					}
				}
				enforce (found);
			}
		}
		debug {writeln ("Scoring: loaded board bonus from ",
		    file_name);}
	}

	void load_tile_values (const string file_name)
	{
		string [] line_list = read_all_lines (file_name);
		enforce (line_list.length == tile_value.length);
		tile_value[] = NA;
		foreach (line; line_list)
		{
			auto cur = line.split ();
			int i = void;
			enforce (cur[0].length == 1);
			if (cur[0][0] == '-')
			{
				i = LET;
			}
			else
			{
				enforce ('A' <= cur[0][0] && cur[0][0] <= 'Z');
				i = cur[0][0] - 'A';
			}
			enforce (tile_value[i] == NA);
			tile_value[i] = to !(int) (cur[1]);
		}
		debug {writeln ("Scoring: loaded tile values from ",
		    file_name);}
	}

	this ()
	{
		load_board_bonus ("data/board-bonus.txt");
		load_tile_values ("data/tile-values.txt");
		bingo = 50;
	}

	void account (ref int score, ref int mult, const BoardCell cur,
	    const int row, const int col) const
	{
		int temp = cur.wildcard ? 0 : tile_value[cur.letter];
		if (cur.active)
		{
			final switch (board_bonus[row][col])
			{
				case Bonus.NO:
					break;
				case Bonus.DL:
					temp *= 2;
					break;
				case Bonus.TL:
					temp *= 3;
					break;
				case Bonus.DW:
					mult *= 2;
					break;
				case Bonus.TW:
					mult *= 3;
					break;
				case Bonus.SIZE:
					assert (false);
			}
		}
		score += temp;
	}

	int calculate (const int vert_score, const int main_score,
	    const int score_mult, const int active_tiles) const
	{
		return vert_score + main_score * score_mult +
		    bingo * (active_tiles == Rack.MAX_SIZE);
	}
}

Scoring global_scoring;
