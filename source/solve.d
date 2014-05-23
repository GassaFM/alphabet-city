module main;

import core.memory;
import std.conv;
import std.stdio;

import board;
import game;
import general;
import problem;
import scoring;
import tilebag;
import trie;

void main ()
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
	auto s = new Scoring ();
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
	GC.collect ();
	foreach (i; 0..1)
	{
		auto g = new Game (ps.problem[i], t, s);
		g.play (10, 0);
		if (i > 0)
		{
			writeln (';');
		}
		writeln ("" ~ to !(char) (i + 'A') ~ ':');
		writeln (g);
		stdout.flush ();
		stderr.writeln ("" ~ to !(char) (i + 'A') ~ ": " ~
			to !(string) (g.best.board.score));
		GC.collect ();
	}
/*
	while (true)
	{
	}
*/
}
