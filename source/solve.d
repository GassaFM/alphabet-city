import core.bitop;
import core.memory;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.stdio;
import std.string;

struct BoardCell
{
	immutable static int SHIFT = 5;
	immutable static int LETTER_MASK = (1 << SHIFT) - 1;
	immutable static int WILDCARD_SHIFT = SHIFT;
	immutable static int CURRENT_SHIFT = SHIFT + 1;

	byte contents;

	static assert (LETTER_MASK > TrieNode.LET);

	byte letter () @property
	{
		return contents & LETTER_MASK;
	}

	byte letter (byte new_letter) @property
	{
		contents = (contents & ~LETTER_MASK) | new_letter;
		return new_letter;
	}

	bool wildcard () @property
	{
		return (contents & (1 << WILDCARD_SHIFT)) != 0;
	}

	byte wildcard (byte new_wildcard) @property
	{
		contents = to !(byte) ((contents & ~(1 << WILDCARD_SHIFT)) |
		    (new_wildcard << WILDCARD_SHIFT));
		return new_wildcard;
	}

	bool current () @property
	{
		return (contents & (1 << CURRENT_SHIFT)) != 0;
	}

	byte current (byte new_current) @property
	{
		contents = to !(byte) ((contents & ~(1 << CURRENT_SHIFT)) |
		    (new_current << CURRENT_SHIFT));
		return new_current;
	}
}

struct Board
{
	immutable static int SIZE = 15;

	BoardCell [SIZE] [SIZE] contents;
	int score;
}

class Scoring
{
	enum BONUS: byte {NO, DW, TW, DL, TL};
	immutable static string [BONUS.max - BONUS.min + 1] BONUS_NAME =
	    ["--", "DW", "TW", "DL", "TL"];
	immutable static int NA = -1;

	BONUS [Board.SIZE] [Board.SIZE] board_bonus;
	int [TrieNode.LET + 1] tile_value;
	int bingo;

	void load_board_bonus (string file_name)
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
				for (auto b = BONUS.min; b <= BONUS.max; b++)
				{
					if (word == BONUS_NAME[b])
					{
						board_bonus[i][j] =
						    to !(BONUS) (b);
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

	void load_tile_values (string file_name)
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
				i = TrieNode.LET;
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
}

struct TrieNode
{
	immutable static int LET = 26;

	int start;
	int mask;

	static assert (mask.sizeof * 8 >= LET + 1);

	bool word () @property
	{
		return (mask & (1 << LET)) != 0;
	}

	bool word (bool new_word) @property
	{
		mask = (mask & ~(1 << LET)) | (new_word << LET);
		return new_word;
	}
}

class Trie
{
	immutable static int NA = -1;
	immutable static int ROOT = 0;
	immutable static char BASE = 'a';

	TrieNode [] contents;

	int next (int pos, int ch)
	{
		int cur_mask = contents[pos].mask;
		if (!(cur_mask & (1 << ch)))
		{
			return NA;
		}
		return contents[pos].start +
		       popcnt (cur_mask & ((1 << ch) - 1));
	}

	this (const char [] [] word_list, int size_hint = 1)
	{
		int nw = to !(int) (word_list.length);
		enforce (isSorted (word_list));
		contents = [TrieNode ()];
		contents.reserve (size_hint);
		auto vp = new int [nw];
		vp[] = ROOT;
		int old_size = 0;
		int total_length = 0;

		foreach (pos; 0..Board.SIZE)
		{
			foreach (i, w; word_list)
			{
				if (pos < w.length)
				{
					contents[vp[i]].mask |=
					    1 << (w[pos] - BASE);
				}
			}

			int new_size = contents.length;
			foreach (j; old_size..new_size)
			{
				contents[j].start = contents.length;
				contents.length += popcnt (contents[j].mask);
			}
			old_size = new_size;

			foreach (i, w; word_list)
			{
				if (pos < w.length)
				{
					vp[i] = next (vp[i], w[pos] - BASE);
					assert (vp[i] != NA);
					if (pos + 1 == w.length)
					{
						contents[vp[i]].word = true;
						total_length += w.length;
					}
	                	}
			}
		}
		debug {writeln ("Trie: loaded ", nw, " words of total length ",
		    total_length, ", created ", contents.length, " nodes");}
	}
}

string [] read_all_lines (string file_name)
{
	string [] res;
	auto fin = File (file_name, "rt");
	foreach (w; fin.byLine ())
	{
		res ~= to !(string) (w);
	}
	return res;
}

void main ()
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 536_340);
	auto s = new Scoring ();
	GC.collect ();
	while (true)
	{
	}
}
