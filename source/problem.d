module problem;

import std.conv;
import std.stdio;
import std.string;

struct Problem
{
	string name;
	string contents;

	this (const string new_name, const string new_contents)
	{
		name = new_name;
		contents = new_contents;
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
