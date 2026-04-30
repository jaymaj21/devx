#ifndef __VARIABLE_H__
#define __VARIABLE_H__

//#undefine CPLUSPLUS
#include<stdio.h>
#include<iostream>
#include<bdd.h>
#include<bvec.h>
#include<limits.h>
#include<vector>
#include<set>
#include<string>
#include<map>
#include<stdarg.h>
#include<assert.h>
using namespace std;

class Domain;
class Variable{

	protected:
		string   _name;
		Domain * _domain;
		int      _fddvarnum;
	public:
		Variable(const string & name,Domain * domain);
		static map<int,Variable*> varTable;
		Domain * getDomain()const;
		string   getName()const;
		int      getMax()const;
		int      numBits()const;
		int      getVarNum()const;
        
};


#endif
