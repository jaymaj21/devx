#ifndef __RELATION_H__
#define __RELATION_H__

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
class Variable;
class TupleCallback;

class Relation{
	protected:
		vector<Variable*>  _vars;
		
        int *        _dummyVars; //used for transitive closure
        int          _dummyCount; //used in TC
		bdd          _dummySet;
		bddPair *    _pairXtoZ;
		bddPair *    _pairYtoZ;
		
		bdd                _theBDD;
        bdd                _lastBDD; //used in computation
                                             //of transitive closure

        
		//friends
		friend void printhandler(FILE * ,int);
	public:
		Relation(Variable * var0,...);
		Relation(const vector<Variable *> &  var);
		~Relation();
		int addTuple(int val0,...);
		int addTuple(const vector<int> & tuple);
		int removeTuple(int val0,...);
		int removeTuple(const vector<int> & tuple);
		bool hasTuple(int val0,...);
		bool hasTuple(const vector<int> & tuple);
		void print(FILE *fp)const;
		Relation * evaluate(Variable * v,int val);
		int evaluateSelf(Variable * v,int val);
		int restrictExistentialSelf(Variable*);
		Relation * restrictExistential(Variable *);
		int restrictUniversalSelf(Variable*);
		Relation * restrictUniversal(Variable *);
		int productSelf(Relation * rel,Variable * var=NULL,bool universal=true);
		Relation * product(Relation * rel,Variable * var=NULL,bool universal=true);
                bool selfJoin();
                bool transitiveClosure();


				void orSelf (Relation * another);
				void andSelf(Relation * another);
				void notSelf();
                /*!
				when dom!=NULL, this function has the semantics of 
				\exists var (dom \implies this)
				when dom is NULL 
				then this function has the semantics of \exists var this
				*/
				void quantifyExists(Relation * dom,...);
				/*! 
				when dom!= NULL , this function  has the semantics of
                \forall var (dom \implies this)
				when dom is NULL ,
				then this function has the semantics of \forall var this
				*/
				void quantifyForall(Relation * dom,...);

				void applyEqualityAndQuantifyFirst(Variable * v1, Variable * v2);

				void setTrue();

				bool isTrue();

				bool isFalse();

				void setFalse();
  
				vector<Variable*>::const_iterator varBegin();

				vector<Variable*>::const_iterator varEnd();

				void traverse(TupleCallback & cb);

				double numTuples();
				/*! Enforces the exact domains of each 
				* variable.
				*/
				void applyVarDomains();
protected:
				

				void reduceDomains();
};

#endif
