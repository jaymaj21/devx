
// Domain: finite integer domain used by the BDD-based relations.
#include"Domain.h"

Domain::Domain(const string & name, int max)
{
	_name=name;
	_max=max;
	++max;
        for (_numBits=0; max > 0; ++_numBits) {
                max >>= 1;
        }

}

int Domain::getMax()const
{
	return _max;

}

string Domain::getName()const
{
	return _name;
}
int Domain::numBits()const
{
	return _numBits;

}


