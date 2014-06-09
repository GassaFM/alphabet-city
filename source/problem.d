module problem;

import std.conv;
import std.stdio;
import std.string;

struct Problem
{
	string name;
	string short_name;
	string contents;
	string virtual;

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
		name = name.dup;
		short_name = short_name.dup;
		contents = contents.dup;
		virtual = virtual.dup;
	}

	string toString () const
	{
		return name ~ ' ' ~ contents;
	}
}

class ProblemSet
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
