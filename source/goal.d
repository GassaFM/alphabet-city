module goal;

import general;

class Goal
{
	immutable static int MAX_SUBGOALS = 6;

	ByteString [] contents;
	int subgoal_mask;
	bool is_flipped;
	ubyte [MAX_SUBGOALS + 1] subgoal_pos;

	int subgoal_start (int number) const
	{
		return subgoal_pos[number] & 0xF;
	}

	int subgoal_end (int number) const
	{
		return subgoal_pos[number] >> 4;
	}

	this ()
	{
	}
}

struct GoalProgress
{
	Goal goal;
	int mask_completed;
}
