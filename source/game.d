module game;

import scoring;
import trie;

class Game (DictClass)
    if (is (DictClass: Object))
{
	DictClass dict;
	Scoring scoring;
}
