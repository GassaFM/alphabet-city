module problem;

import std.conv;
import std.exception;
import std.stdio;
import std.string;

import general;
import tile_bag;

struct Problem
{
	string name;
	string short_name;
	string contents;
	string virtual;

	static Problem clean (const ref Problem original)
	{
		char [] new_contents = to !(char []) (original.contents);
		foreach (ref c; new_contents)
		{
			if (c != '?')
			{
				c &= ~TileBag.IS_RESTRICTED;
			}
		}
		char [] new_virtual = to !(char []) (original.virtual);
		foreach (ref c; new_virtual)
		{
			if (c != '?')
			{
				c &= ~TileBag.IS_RESTRICTED;
			}
		}
		return Problem (original.name, new_contents, new_virtual);
	}

	static Problem restrict_back (const ref Problem original,
	    ByteString word)
	{
		assert (original.virtual.length == 0); // not implemented
		char [] new_contents = to !(char []) (original.contents);
		foreach (letter; word)
		{
			bool found = false;
			foreach_reverse (ref c; new_contents)
			{
				if (letter + 'A' == c)
				{
					found = true;
					c |= TileBag.IS_RESTRICTED;
					break;
				}
			}
			if (!found)
			{ // use wildcard
				foreach_reverse (ref c; new_contents)
				{
					if (c == '?' || c == 'A' + LET)
					{
						found = true;
						c = 'a' + LET;
						break;
					}
				}
			}
			enforce (found);
		}
		return Problem (original.name, new_contents);
	}

	int count_restricted () const
	{
		int res = 0;
		foreach (c; contents)
		{
			res += (c != '?') &&
			    ((c & TileBag.IS_RESTRICTED) != 0);
		}
		return res;
	}

	this (const char [] new_name, const char [] new_contents,
	    const char [] new_virtual = "")
	{
		name = to !(string) (new_name);
		short_name = toLower (to !(string) (name[0]));
		contents = to !(string) (new_contents);
		virtual = to !(string) (new_virtual);
	}

	this (this)
	{
		name = to !(typeof (name)) (name.dup);
		short_name = to !(typeof (short_name)) (short_name.dup);
		contents = to !(typeof (contents)) (contents.dup);
		virtual = to !(typeof (virtual)) (virtual.dup);
	}

	string toString () const
	{
		return name ~ " (" ~ to !(string) (count_restricted) ~ '/' ~
		    to !(string) (contents.length) ~ ") " ~ contents;
	}
}

final class ProblemSet
{
	Problem [] problem;

	this (const char [] [] line_list)
	{
		foreach (line; line_list)
		{
			auto temp = line.split ();
			problem ~= Problem (to !(string) (temp[0]),
			    to !(string) (temp[1]));
		}
		debug {writeln ("ProblemSet: loaded ", problem.length,
		    " problems");}
	}
}
