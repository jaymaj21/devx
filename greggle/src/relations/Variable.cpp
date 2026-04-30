#include"Domain.h"
#include"Variable.h"
map<int,Variable*> Variable::varTable;
 Domain * Variable::getDomain()const
{
	return _domain;
}


int Variable::getVarNum()const
{
	return _fddvarnum;
}
Variable::Variable(const string & name, Domain * domain):_name(name),_domain(domain)
{
 
		int max=getMax()+1;
		_fddvarnum= fdd_extdomain(&max,1);
		varTable[_fddvarnum]=this;
                
}
int Variable::numBits()const
{
	return _domain->numBits();
}
int Variable::getMax()const
{
	return _domain->getMax();
}
string Variable::getName()const
{
       return _name;
}


