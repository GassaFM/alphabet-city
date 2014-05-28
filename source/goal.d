module goal;

import core.bitop;
import std.algorithm;
import std.conv;
import std.exception;
import std.stdio;
import std.string;

import board;
import general;
import tilebag;
import trie;

class Goal
{
	ByteString word;
	int mask_forbidden;
	byte row;
	byte col;
	bool is_flipped;
	int letter_bonus;

	int [] calc_times (TileBag tile_bag, int lower_limit = 0,
	    int upper_limit = TOTAL_TILES, int wildcards = 0)
	{
		assert (wildcards == 0); // wildcards > 0: not implemented yet
		auto taken = new bool [tile_bag.contents.length];
		bool ok;
		int [] res;
		foreach (pos, letter; word)
		{
			if ((mask_forbidden & (1 << pos)) != 0)
			{
				ok = false;
				for (int num = upper_limit - 1;
				    num >= lower_limit; num--)
				{
					auto tile = tile_bag.contents[num];
					if (!taken[num] && tile == letter)
					{
						res ~= to !(int) (num);
						taken[num] = true;
						ok = true;
						break;
					}
				}
				if (!ok)
				{
					break;
				}
			}
		}
		if (ok)
		{
		        sort (res);
		        reverse (res);
			return res;
		}
		else
		{
			return new int [0];
		}
	}

	this (const byte [] new_word, int new_mask_forbidden,
	    byte new_row, byte new_col, bool new_is_flipped,
	    int new_letter_bonus = 100)
	{
		word = new_word.idup;
		mask_forbidden = new_mask_forbidden;
		row = new_row;
		col = new_col;
		is_flipped = new_is_flipped;
		letter_bonus = new_letter_bonus;
	}

	override string toString () const
	{
		string res;
		foreach (i, c; word)
		{
			res ~= c +
			    (((mask_forbidden & (1 << i)) > 0) ? 'A' : 'a');
		}
		res ~= ' ' ~ to !(string) (row);
		res ~= ' ' ~ to !(string) (col);
		res ~= ' ' ~ to !(string) (is_flipped);
		return res;
	}

	override int opCmp (Object other)
	{
		return false;
	}
}

struct GoalProgress
{
	Goal goal;
	bool is_completed;

	this (Goal new_goal)
	{
		goal = new_goal;
	}
}

static class GoalBuilder
{
	static Goal [] build_goals (Trie trie)
	{
		auto cur_word = new byte [Board.SIZE];
		Goal [] res;

		void recur (int mask, int vm, int lm, int vs, int ls)
		{
			if (lm == Board.SIZE)
			{
				if (trie.contents[vm].word &&
				    ((ls <= 1) || trie.contents[vs].word))
				{
					res ~= new Goal (cur_word[0..lm],
					    mask, 0, 0, false);
				}
				return;
			}

			foreach (byte ch; 0..LET)
			{
				cur_word[lm] = ch;
				int nvm = trie.contents[vm].next (ch);
				int nvs = trie.contents[vs].next (ch);
				if ((popcnt (mask) < Rack.MAX_SIZE) &&
				    ((ls <= 1) || trie.contents[vs].word) &&
				    nvm != NA)
				{ // forbid current letter
					recur (mask | (1 << lm),
					    nvm, lm + 1, 0, 0);
				}

				if (lm % 7 != 0 && nvm != NA && nvs != NA)
				{ // use current letter
					recur (mask,
					    nvm, lm + 1, nvs, ls + 1);
				}
			}
		}

		recur (0, 0, 0, 0, 0);
		sort !((a, b) => toLower (to !(string) (a.word)) <
		    toLower (to !(string) (b.word))) (res);

		debug {writeln ("GoalBuilder: built ", res.length, " goals");}
		return res;
	}

	static Goal [] build_goals (const char [] [] line_list)
	{
		Goal [] res;
		res.reserve (line_list.length);
		foreach (line; line_list)
		{
			byte [] cur_word;
			cur_word.reserve (Board.SIZE);
			int mask = 0;
			foreach (i, ch; line)
			{
				if ('A' <= ch && ch <= 'Z')
				{
					cur_word ~= to !(byte) (ch - 'A');
					mask |= 1 << i;
				}
				else if ('a' <= ch && ch <= 'z')
				{
					cur_word ~= to !(byte) (ch - 'a');
				}
				else
				{
					enforce (false);
				}
			}
			res ~= new Goal (cur_word, mask, 0, 0, 0);
		}
		debug {writeln ("GoalBuilder: loaded ", res.length, " goals");}
		return res;
	}
}

class CompoundGoal
{
	ByteString word;
	CompoundGoal [] sub;
	int mask_forbidden;
	byte row;
	byte col;
	bool is_flipped;

	this ()
	{
	}
}

struct CompoundGoalProgress
{
	immutable static int MAIN_COMPLETED = 1 << 30;

	CompoundGoal main_goal;
	int mask_completed;

	bool is_completed () const
	{
		return (mask_completed & MAIN_COMPLETED) != 0;
	}

	this (CompoundGoal new_main_goal)
	{
		main_goal = new_main_goal;
	}
}