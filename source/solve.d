module main;

import core.memory;
import std.conv;
import std.stdio;

import board;
import game;
import fifteen;
import general;
import problem;
import scoring;
import tilebag;
import trie;

void main ()
{
	auto t = new Trie (read_all_lines ("data/words.txt"), 540_130);
//	auto t = new Trie (read_all_lines ("data/words8.txt"), 233_691);
	auto s = new Scoring ();
	auto ps = new ProblemSet (read_all_lines ("data/problems.txt"));
/*
	auto lws = new LongWordSet (read_all_lines ("data/words.txt"), s, t);
	foreach (lw; lws.contents)
	{
		writeln (lw);
		foreach (p; ps.problem)
		{
			writeln (p);
			foreach (k; 0..3)
			{
				writeln (lw.possible (p, k));
			}
		}
	}
*/
	GC.collect ();
	foreach (i; 1..2)
	{
		auto g = new Game (ps.problem[i], t, s);
		g.play (20000, 0);
		if (i > 0)
		{
			writeln (';');
		}
		writeln (ps.problem[i].name);
		writeln (g);
		stdout.flush ();
		stderr.writeln ("" ~ to !(char) (i + 'A') ~ ": " ~
			to !(string) (g.best.board.score));
		GC.collect ();
	}
}
