//#undefine CPLUSPLUS
#ifndef __DOMAIN_H__
#define __DOMAIN_H__

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

class Domain{
	protected:
		int _max;
		int _numBits;
		string _name;
		
	public:
		Domain(const string & name,int max);
		int getMax()const;
		int numBits()const;
		string getName()const;
};
#endif
