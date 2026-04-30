//#undefine CPLUSPLUS
#include"Domain.h"
#include"Variable.h"
#include"Relation.h"
#include<algorithm>
#include"TupleCallback.h"
#include<bdd.h>


Relation::Relation(const vector<Variable *> & variables )
{
	_lastBDD=bddfalse;
	_theBDD=bddfalse;
	_dummySet=bddfalse;
    
	_pairXtoZ=NULL;
	_pairYtoZ=NULL;

	_dummyVars=NULL;
	_dummyCount=0;
	
	int max;
	vector<Variable*>::const_iterator iter;
	for(iter=variables.begin();iter!=variables.end();++iter){
		_vars.push_back(*iter);
	}
	

}
Relation::Relation(Variable * var0,...)
{

	va_list arg;
	va_start(arg,var0);
	Variable *v;
	v=var0;
	_vars.push_back(v);
	while(1) {
		v=va_arg(arg,Variable*);
		if(v==NULL)break;
		_vars.push_back(v);
	}

	_lastBDD=bddfalse;
	_theBDD=bddfalse;
	_dummySet=bddfalse;
    
	_pairXtoZ=NULL;
	_pairYtoZ=NULL;

	_dummyVars=NULL;
	_dummyCount=0;




}
Relation::~Relation()
{
	if(_pairXtoZ!=NULL)bdd_freepair(_pairXtoZ);
	if(_pairYtoZ!=NULL)bdd_freepair(_pairYtoZ);
	if(_dummyVars!=NULL)delete []_dummyVars;

}
bool Relation::hasTuple(const vector<int>& aMinTerm)
{

	vector<Variable*>::const_iterator variter;
	vector<int>::const_iterator valiter;
	bdd abdd=bddtrue;
	for(variter=_vars.begin(),valiter=aMinTerm.begin();
		variter!=_vars.end();++variter,++valiter){
			assert((*variter)->getMax() >=(*valiter));
			assert(*valiter >= 0);
			// Use FDD equality instead of bitvector encoding.
			abdd = abdd & fdd_ithvar((*variter)->getVarNum(), *valiter);
		}
		bdd result=_theBDD & abdd;
		return !(result==bddfalse);
}


bool Relation::transitiveClosure()
{

	_lastBDD=bddfalse;
	
	assert(_vars.size()%2==0);
	int nvar=_vars.size()/2;
	assert(nvar!=0);
	for(int i=0;i<nvar;++i){
		assert(_vars[i]->getDomain()==_vars[nvar+i]->getDomain());
	}
	if(_dummyCount!=nvar){
		
		assert(_dummyCount==0);
		assert(_dummyVars==NULL);
		_dummyVars=new int[nvar];
		_pairXtoZ=bdd_newpair();
		_pairYtoZ=bdd_newpair();
		for(int i=0;i<nvar;++i){
			int max=fdd_domainsize(_vars[i]->getVarNum());
			int fddvarnew=fdd_extdomain(&max,1);
			_dummyVars[i]=fddvarnew;
			fdd_setpair(_pairXtoZ,_vars[i]->getVarNum(),fddvarnew);
			fdd_setpair(_pairYtoZ,_vars[i+nvar]->getVarNum(),fddvarnew);
		}
		_dummySet=fdd_makeset(_dummyVars,nvar);
	}
   


	while(1)
	{
		if(_theBDD==_lastBDD) break;
		bool retval=selfJoin();
		if(!retval) return false;

	}
	return true;



}


// The following should work in a very special case.
// If the relation involves an even number of variables
// and if Dom(var(i))=Dom(var(n/2 + i))
bool Relation::selfJoin()
{
	_lastBDD=_theBDD;
	bdd bddXZ=bdd_replace(_theBDD,_pairYtoZ);
	bdd bddZY=bdd_replace(_theBDD,_pairXtoZ);
    bdd intermediatedd=bdd_apply(bddXZ,bddZY,bddop_and);
	bdd intermediatedd2=bdd_exist(intermediatedd,_dummySet);
	_theBDD=bdd_apply(intermediatedd2,_theBDD,bddop_or);
	//cout<<fddset<<_theBDD<<endl;
	//cout<<"--------------"<<endl;
	//cout<<fddset<<_lastBDD<<endl;
	return true;
}


// Specialized algorithm
// Assume that this relation has arity 5
// Convention : n1,e1,s1,n2,s2
/*
Relation * Relation::allWalksAux(vector<int> & accepting,int deadState
,int deadNode)
{


assert(_vars.size()!=5)
vector<Variable *> vars;
for(int i=0;i<5;++i){
if(i!=1) {
vars.push_back(_vars[i]);
}
}
bdd fOld;
Relation * f=new Relation("F",vars);
if(_vars[0]&&_vars[1])
while(1)
{

if(_theBDD==_lastBDD) break;
bool retval=selfJoin();
if(!retval) return false;

}







}
*/


bool Relation::hasTuple(int entry0,...) // parse it according to the initialization
{
	static vector<int> entry;
	entry.clear();
	va_list arg;
	va_start(arg,entry0);
	int e;
	e=entry0;
	entry.push_back(e);
	for (unsigned int i=0;i<_vars.size()-1;++i){
		e=va_arg(arg,int);
		entry.push_back(e);
	}
	va_end(arg);
	return hasTuple(entry);
}


/*
Compute different acceptance condition, 
what are different from the one already implemented ?
  Buchi acceptance condition says that the paths will continue to reach
  some accepting state infinitely many times.
   i.e. in the transitive closure on the product automaton 
        - there has to be some product state that is both self reachable 
		  and reachable from one of the start states.
		  i.e. Buchi_Acceptance(i) = exists j such that TC(i,j) & TC(j,j)
          why is buchi DFA construction doubly exponential ?
		  Why should our DFA construction fail ?   
		 

  */

int Relation::addTuple(const vector<int>& aMinTerm)
{
	vector<Variable*>::const_iterator variter;
	vector<int>::const_iterator valiter;

	bdd abdd=bddtrue;
	for(variter=_vars.begin(),valiter=aMinTerm.begin();
		variter!=_vars.end();++variter,++valiter){
			assert(((*variter)->getMax() >=(*valiter)) &&(*valiter >=0));
			// Use FDD equality instead of bitvector encoding.
			abdd = abdd & fdd_ithvar((*variter)->getVarNum(), *valiter);
		}
		_theBDD=_theBDD | abdd;
		return 1;

}
Relation const * currentRelation=NULL;
void printhandler(FILE* fp,int var)
{
	if(currentRelation!=NULL){

		map<int,Variable*>::const_iterator foundPair=

			Variable::varTable.find(var);

		if(foundPair!=Variable::varTable.end()){

			fprintf(fp,"%s(%s)",
				(foundPair->second->getDomain()->getName()).c_str(),
				foundPair->second->getName().c_str());

		}

		else {


			fprintf(fp,"%d",var);

		}

	}

}
void Relation::print(FILE *fp)const
{
	currentRelation=this;
	fdd_file_hook(printhandler);
	fdd_fprintset(fp,_theBDD);
	fdd_file_hook(NULL);
	currentRelation=NULL;
}
int Relation::removeTuple(const vector<int>& aMinTerm)
{

	vector<Variable*>::const_iterator variter;
	vector<int>::const_iterator valiter;

	bdd abdd=bddtrue;
	for(variter=_vars.begin(),valiter=aMinTerm.begin();
		variter!=_vars.end();++variter,++valiter){
			assert((*variter)->getMax() >=(*valiter));
			int numbits=(*variter)->numBits();
			bvec c=bvec_con(numbits,*valiter);
			bvec v=bvec_varfdd((*variter)->getVarNum());
			abdd=abdd & (c==v);
		}
		_theBDD=_theBDD &  (!abdd);
		return 1;

}

int Relation::addTuple(int entry0,...) // parse it according to the initialization
{
	static int nums[100];
	int cnt=0;

	//printf("\n(tuple ");
 	//static vector<int> entry;
	//entry.clear();
	va_list arg;
	va_start(arg,entry0);
	int e;
	e=entry0;
	//printf(" %d ", e);
	assert(e>=0);
	nums[cnt]=e;
	//entry.push_back(e);
	for (unsigned int i=0;i<_vars.size()-1;++i){
		//printf("[[%d]]\n",_vars.size());
		e=va_arg(arg,int);
		//printf(" %d " ,e);
		assert(e>=0);
		++cnt;
		//entry.push_back(e);
		nums[cnt]=e;
	}
	//printf(")");
	//addTuple(entry);
    bdd abdd=bddtrue;
	
	for(int  iter=0;iter<=cnt;++iter){
		//printf("<<%d,",_vars.size());
		Variable * thisVar=_vars[iter];
		//printf("%d>>\n",_vars.size());
		assert(thisVar->getMax() >= nums[iter] &&(nums[iter] >=0));
			int numbits=thisVar->numBits();
			bvec c=bvec_con(numbits,nums[iter]);
			bvec v=bvec_varfdd(thisVar->getVarNum());
			abdd=abdd & (c==v);
	}
	_theBDD=_theBDD | abdd;

	va_end(arg);
	return 1;
}

int Relation::removeTuple(int entry0,...) // parse it according to the initialization
{
	static vector<int> entry;
	entry.clear();
	va_list arg;
	va_start(arg,entry0);
	int e;
	e=entry0;
	entry.push_back(e);
	for (unsigned int i=0;i<_vars.size()-1;++i){
		e=va_arg(arg,int);
		entry.push_back(e);
	}
	removeTuple(entry);
	va_end(arg);
	return 1;
}


Relation *  Relation::evaluate(Variable * var,int value)
{
	//TODO
	return NULL;

}
int Relation::evaluateSelf(Variable * var, int value)
{

	//TODO
	return 0;
}

Relation *  Relation::restrictExistential(Variable * var)
{
	//TODO
	return NULL;
}
int Relation::restrictExistentialSelf(Variable * var)
{
	//TODO
	return 0;
}

Relation *  Relation::restrictUniversal(Variable * var)
{
	//TODO
	return NULL;
}
int Relation::restrictUniversalSelf(Variable * var)
{

	//TODO
	return 0;
}
int Relation::productSelf(Relation *rel, Variable *var,bool universal)
{

	//TODO
	return 0;
}

Relation *  Relation::product(Relation * rel,Variable * var,bool universal)
{
	//TODO
	return NULL;
}


void Relation::andSelf(Relation * another)
{
	//Remember to augment the list of variables maintained by 
	// this
	vector<Variable*>::const_iterator iter;
	vector<Variable*>::const_iterator iter2;

	for(iter=another->varBegin();iter!=another->varEnd();++iter){
		for(iter2=_vars.begin();iter2!=_vars.end();++iter2){
			if((*iter2)==*iter){
				break;
			}
		}
		if(iter2==_vars.end())_vars.push_back(*iter);
	}
	_theBDD=_theBDD & another->_theBDD;

}
void Relation::orSelf(Relation * another)
{
	

    vector<Variable*>::const_iterator iter;
	vector<Variable*>::const_iterator iter2;

	for(iter=another->varBegin();iter!=another->varEnd();++iter){
		for(iter2=_vars.begin();iter2!=_vars.end();++iter2){
			if((*iter2)==*iter){
				break;
			}
		}
		if(iter2==_vars.end())_vars.push_back(*iter);
	}
	_theBDD=_theBDD | another->_theBDD;

}
double Relation::numTuples()
{
	//need to return the satcount;
	bdd varset;
	int * fddvars=new int[_vars.size()];
	int i;
	vector<Variable *>::const_iterator variter;
	for(i=0,variter=_vars.begin();variter!=_vars.end();++variter,++i){
		fddvars[i]=(*variter)->getVarNum();
	}
	varset=fdd_makeset(fddvars,_vars.size());
	delete [] fddvars;
	return bdd_satcountset(_theBDD,varset);

}
vector<Variable*>::const_iterator Relation::varBegin()
{
	return _vars.begin();
}
vector<Variable*>::const_iterator Relation::varEnd()
{
	return _vars.end();
}

void Relation::notSelf()
{
	// apply bdd not operation on self
	_theBDD=!_theBDD;
}

void Relation::applyEqualityAndQuantifyFirst(Variable * v1,Variable * v2)
{
	
	bvec v1vec=bvec_varfdd(v1->getVarNum());
	bvec v2vec=bvec_varfdd(v2->getVarNum());
	_theBDD=_theBDD& (v1vec == v2vec);
    quantifyExists(NULL,v1,NULL);
}

void Relation::quantifyExists(Relation * dom,...)
{
	//Start extraction of polyadic arguments
	va_list arg;
	va_start(arg,dom);
	// check that dom has no new variable , not present in this
	// assert on that
	if(dom!=NULL){
		vector<Variable*>::const_iterator iter;
		for(iter=dom->varBegin();iter!=dom->varEnd();++iter){
			vector<Variable*>::iterator found=find(_vars.begin(),
				_vars.end(),*iter);
			assert(found!=_vars.end());
		}
	}
	Variable * v;
	// imposing a hard limit on
	// the number of fdd variables 
	// that can be quantified in one go
	static int fddvars[100];
	int        numvars=0;
	while(1) {
		v=va_arg(arg,Variable*);
		if(v==NULL)break;
		else{
			vector<Variable*>::iterator found=
				find(_vars.begin(),_vars.end(),v);
			if(found!=_vars.end()){
				fddvars[numvars]=v->getVarNum();
				++numvars;
				_vars.erase(found);
			}
		}
	}
	// quantify over the given variable
	if(numvars>0){
		if(dom!=NULL){
			_theBDD= _theBDD & dom->_theBDD;
		}
		bdd varset=fdd_makeset(fddvars,numvars);
		_theBDD=bdd_exist(_theBDD,varset);    
	}

	// apply the quantification
	// Remove the Variable-s from the vectors and sets maintained by this
	// be happy
}
void Relation::quantifyForall(Relation * dom,...)
{
	//Start extraction of polyadic arguments
	va_list arg;
	va_start(arg,dom);
	// check that dom has no new variable , not present in this
	// assert on that
	if(dom!=NULL){
		vector<Variable*>::const_iterator iter;
		for(iter=dom->varBegin();iter!=dom->varEnd();++iter){
			vector<Variable*>::iterator found=find(_vars.begin(),
				_vars.end(),*iter);
			assert(found!=_vars.end());
		}
	}
	Variable * v;
	// imposing a hard limit on
	// the number of fdd variables 
	// that can be quantified in one go
	static int fddvars[100];
	int        numvars=0;
	while(1) {
		v=va_arg(arg,Variable*);
		if(v==NULL)break;
		else{
			vector<Variable*>::iterator found=
				find(_vars.begin(),_vars.end(),v);
			if(found!=_vars.end()){
				fddvars[numvars]=v->getVarNum();
				++numvars;
				_vars.erase(found);

			}
		}
	}
	// quantify over the given variable
	if(numvars>0){
		if(dom!=NULL){
			_theBDD=bdd_imp(dom->_theBDD,_theBDD);

		}
		bdd varset=fdd_makeset(fddvars,numvars);
		_theBDD=bdd_forall(_theBDD,varset);    
	}

	// apply the quantification
	// Remove the Variable-s from the vectors and sets maintained by this
	// be happy 


}

void Relation::setTrue()
{
	_theBDD=bddtrue;
};
void Relation::setFalse()
{
	_theBDD=bddfalse;
};

bool Relation::isTrue()
{
	return _theBDD==bddtrue;
}
bool Relation::isFalse()
{
	return _theBDD==bddfalse;
}
void rel_traverse(const bdd &r,TupleCallback &cb);

void Relation::traverse(TupleCallback & cb)
{
	applyVarDomains();
	reduceDomains();// is this indispensable ?
	//applyVarDomains();
	rel_traverse(_theBDD,cb);
	
}

void Relation::applyVarDomains()
{
   // Should be similar to addTuple
	vector<Variable*>::const_iterator variter;
	
	bdd abdd=bddtrue;
	for(variter=_vars.begin();
		variter!=_vars.end();++variter){
			int numbits=(*variter)->numBits();
			//printf("<<%d>>",(*variter)->getMax());
			bvec c=bvec_con(numbits,(*variter)->getMax());
			bvec v=bvec_varfdd((*variter)->getVarNum());
			abdd=abdd & (v<c);
		}
		_theBDD=_theBDD & abdd;
		return ;

}

void Relation::reduceDomains()
{
	
	// Should check _theBDD 
	// to scan all variables in it.
	// keep only those variables in _vars that are there in _theBDD
    // this should be done before doing applyVarDomains
    int numVarsToKeep;
	_vars.clear();
    int * varsToKeep;
    fdd_scanset(_theBDD,varsToKeep,numVarsToKeep);
	for(int i=0;i<numVarsToKeep;++i){
		static map<int,Variable*>::iterator found;
		found=Variable::varTable.find(varsToKeep[i]);
		assert(found!=Variable::varTable.end());
        _vars.push_back(found->second);	
	}
	free(varsToKeep); //

}
