module general;

import std.conv;
import std.stdio;
import std.typecons;

immutable static int LET = 26;
immutable static int LET_BITS = 5;
immutable static int LET_MASK = (1 << LET_BITS) - 1;
immutable static int NA = -1;

static assert ((LET + 1) <= (1 << LET_BITS));

string [] read_all_lines (const string file_name)
{
	string [] res;
	auto fin = File (file_name, "rt");
	foreach (w; fin.byLine ())
	{
		res ~= to !(string) (w);
	}
	return res;
}

struct Pair
{
	int x;
	int y;

	string toString () const
	{
		return "(" ~ to !(string) (x) ~ ", " ~ to !(string) (y) ~ ")";
	}
}
