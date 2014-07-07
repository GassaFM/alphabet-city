module search.beam;

import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.stdio;
import std.traits;

T [] inverse_permutation (T) (T [] perm)
{
	auto n = to !(int) (perm.length);
	auto res = new T [n];
	foreach (i; 0..n)
	{
		res[perm[i]] = i;
	}
	return res;
}

private final class BeamSearchStorage (alias get_hash,
    alias process_post_dup,
    alias compare_inner,
    State)
//    if (is (HashType get_hash (State.init)))
{
	private State [] payload;
	int width;
	int buffer_size;
	bool ready;

	void repack ()
	{
		alias HashType = ReturnType !(get_hash);
		int [HashType] marked;
		foreach (pos, ref cur_state; payload)
		{
			HashType cur_hash = get_hash (cur_state);
			if (cur_hash in marked)
			{
				int stored_pos = marked[cur_hash];
				int better = compare_inner (cur_state,
				    payload[stored_pos]);
				if (better > 0)
				{
					payload[stored_pos] = cur_state;
				}
				cur_state = State.init;
			}
			else
			{
				marked[cur_hash] = cast (int) pos;
			}

		}
		int new_length = min (payload.length, width);
		auto perm = (cast (int) (payload.length))
		    .iota ().array ();
/*
		partialSort !((a, b) => compare_inner (payload[a],
		    payload[b]) > 0, SwapStrategy.unstable)
		    (perm, new_length);
*/
		sort !((a, b) => compare_inner (payload[a],
		    payload[b]) > 0, SwapStrategy.stable)
		    (perm);
		auto inv = inverse_permutation (perm);

		foreach (i; 0..new_length)
		{
			int j = perm[i];
			if (i != j)
			{
				swap (payload[i], payload[j]);
				swap (perm[inv[i]], perm[inv[j]]);
				swap (inv[i], inv[j]);
			}
		}

		payload.length = new_length;
		payload.assumeSafeAppend ();
		assert (isSorted !((a, b) => compare_inner (a, b) > 0)
		    (payload));
	}

	ref State put (ref State cur_state)
	{
		if (payload.empty)
		{
			payload.reserve (width + buffer_size);
		}

		if (payload.length >= payload.capacity)
		{
			repack ();
			assert (payload.length < payload.capacity);
		}

		payload ~= cur_state;

		if (process_post_dup (payload[$ - 1]))
		{
			ready = false;
			return payload[$ - 1];
		}
		else
		{
			payload.length--;
			payload.assumeSafeAppend ();
			return cur_state;
		}
	}

	bool empty () @property
	{
		return payload.length == 0;
	}

	ref State front () @property
	{
		if (!ready)
		{
			repack ();
			assert (!empty);
		}
//		writeln (payload[0]);
		return payload[0];
	}

	void popFront ()
	{
		payload = payload[1..$];
	}

	this (int new_width, int new_buffer_size)
	in
	{
		assert (new_width > 0);
		assert (new_buffer_size > 0);
	}
	body
	{
		width = new_width;
		buffer_size = new_buffer_size;
	}
}

private final class BeamSearch (int max_level,
    alias get_level,
    alias get_hash,
    alias gen_next,
    alias process_pre_dup,
    alias process_post_dup,
    alias compare_best,
    alias compare_inner,
    State)
{
	int width;
	int depth;

	alias CurStorage = BeamSearchStorage !(get_hash, process_post_dup,
	    compare_inner, State);
	CurStorage [] storage;
	State best;

	this (int new_width, int new_depth)
	{
		width = new_width;
		depth = new_depth;

		storage = new CurStorage [max_level + 1];
		foreach (ref line; storage)
		{
			line = new CurStorage (width, width);
		}
	}

	void visit (ref State cur_state, int cur_depth)
	{
		foreach (ref State next_state; gen_next (cur_state))
		{
			put (next_state);
			if (cur_depth > 0)
			{
				visit (next_state, cur_depth - 1);
			}
		}
	}

	void check_best (ref State cur_state)
	{
		if (compare_best (best, cur_state) < 0)
		{
			best = cur_state;
		}
	}

	void put (ref State cur_state)
	{
		if (!process_pre_dup (cur_state))
		{
			return;
		}
		int cur_level = get_level (cur_state);
		if (cur_level > max_level)
		{
			return;
		}
		check_best (storage[cur_level].put (cur_state));
	}

	State go (StateRange) (StateRange init_states)
	    if (isForwardRange !(StateRange) &&
	        (ElementType !(StateRange).init is State.init))
	{
		foreach (cur_state; init_states)
		{
			put (cur_state);
		}

		foreach (level; 0..max_level + 1)
		{
			version (debug_beam)
			{
				writeln ("beam search: at level ", level,
				    ", length ",
				    storage[level].payload.length);
			}
			version (verbose)
			{
				writeln ("filled ", level, " tiles");
				stdout.flush ();
			}
			int counter = 0;
			foreach (cur_state; storage[level])
			{
				version (verbose)
				{
					if (min (counter, min (width,
					    storage[level].payload.length) -
					    1 - counter) < 10)
					{
						writeln ("at:");
						writeln (cur_state);
						stdout.flush ();
					}
				}
				visit (cur_state, depth);
				counter++;
			}
		}

//		best.board.normalize ();
		return best;
	}
}

State beam_search (int max_level,
    alias get_level,
    alias get_hash,
    alias gen_next,
    alias process_pre_dup,
    alias process_post_dup,
    alias compare_best,
    alias compare_inner,
    State, StateRange)
    (StateRange init_states, int width, int depth)
    if (isForwardRange !(StateRange) &&
        (ElementType !(StateRange).init is State.init))
{
	return (new BeamSearch !(max_level, get_level, get_hash, gen_next,
	    process_pre_dup, process_post_dup,
	    compare_best, compare_inner, State)
	    (width, depth)).go (init_states);
}

unittest
{
	auto a = [2, 3, 5];

	auto b = beam_search !(100, a => a, (int a) => a,
	    a => [a * 7, a * 11, a * 13],
	    a => true, a => true,
	    (a, b) => (a > b) - (a < b),
	    (a, b) => (a > b) - (a < b),
	    int) (a, 10, 1);
	assert (b == 2 * 7 * 7);
	auto c = beam_search !(100, a => a, (int a) => a,
	    a => [a * 7, a * 11, a * 13],
	    a => true, a => true,
	    (a, b) => (a > b) - (a < b),
	    (a, b) => (a > b) - (a < b),
	    int, int []) (a, 1, 0);
	assert (c == 2 * 7 * 7);
	auto d = beam_search !(100, a => a, (int a) => a,
	    a => [a * 2, a * 3, a * 5],
	    a => true, a => true,
	    (a, b) => (a > b) - (a < b),
	    (a, b) => (a > b) - (a < b),
	    int, int []) (a, 1, 2);
	assert (d == 100);
}
