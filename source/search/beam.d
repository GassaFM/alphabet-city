module search.beam;

import std.algorithm;
import std.array;
import std.conv;
import std.range;
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

class BeamSearchStorage (alias get_hash,
    alias check_good_post_dup,
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
		foreach (ref cur_state; payload)
		{
			HashType cur_hash = get_hash (cur_state);
			if (cur_hash in marked)
			{
				int better = compare_inner (cur_state,
				    payload[marked[cur_hash]]);
				if (better > 0)
				{
					payload[marked[cur_hash]] = cur_state;
				}
				cur_state = State.init;
			}

			int new_length = min (payload.length, width);
			auto perm = new_length.iota ().array ();
			partialSort !((a, b) => compare_inner (payload[a],
			    payload[b]) > 0, SwapStrategy.unstable)
			    (perm, new_length);
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
	}

	void put (ref State cur_state)
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

		if (check_good_post_dup (payload))
		{
			ready = false;
		}
		else
		{
			payload.length--;
			payload.assumeSafeAppend ();
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

private class BeamSearch (int max_level,
    alias get_level,
    alias get_hash,
    alias gen_next,
    alias check_good_pre_dup,
    alias check_good_post_dup,
    alias compare_best,
    alias compare_inner,
    State)
{
	int width;
	int depth;

	alias CurStorage = BeamSearchStorage !(get_hash, check_good_post_dup,
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
		if (!check_good_pre_dup (cur_state))
		{
			return;
		}
		int cur_level = get_level (cur_state);
		if (cur_level > max_level)
		{
			return;
		}
		check_best (cur_state);
		storage[cur_level].put (cur_state);
	}

	State go (StateRange) (StateRange init_states)
	    if (isForwardRange !(StateRange) &&
	        is (typeof ((ElementType !(StateRange).init == State.init))))
	{
		foreach (cur_state; init_states)
		{
			put (cur_state);
		}

		foreach (level; 0..max_level + 1)
		{
			foreach (cur_state; storage[level])
			{
				visit (cur_state, depth);
			}
		}

		return best;
	}
}

State beam_search (int max_level,
    alias get_level,
    alias get_hash,
    alias gen_next,
    alias check_good_pre_dup,
    alias check_good_post_dup,
    alias compare_best,
    alias compare_inner,
    State, StateRange)
    (StateRange init_states, int width, int depth)
    if (isForwardRange !(StateRange) &&
        is (typeof ((ElementType !(StateRange).init == State.init))))
{
	return new BeamSearch !(max_level, get_level, get_hash, gen_next,
	    check_good_pre_dup, check_good_post_dup,
	    compare_best, compare_inner, State)
	    (width, depth).go (init_states);
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
