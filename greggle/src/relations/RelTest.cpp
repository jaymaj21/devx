#include"Domain.h"
#include"Variable.h"
#include"Relation.h"
#include"TupleCallback.h"

class CB1:public TupleCallback
{
	Relation * _rel;
public:
	CB1(Relation * rel):_rel(rel)
	{
	}
	virtual void execute(map<Variable*,vector<int>*>& tuple)
	{	
		initialize(tuple);
		recurseBindings(tuple);
		deallocate(tuple);
	}
protected:
    int v1;
	int v2;
	map<Variable*,int*>   varval;
	map<string,Variable*> namevar;
	virtual void initialize(map<Variable*,vector<int>*> tuple)
	{
		map<Variable*,vector<int>*>::iterator iter;
		for(iter=tuple.begin();iter!=tuple.end();++iter){
			namevar[iter->first->getName()]=iter->first;
		}
		map<string,Variable*>::iterator found;
		//boilerplate so far
        //some generated code here
        
		//begin{generated}
		found=namevar.find("v1");
		if(found!=namevar.end())varval[found->second]=&v1;
        v1=0;

		found=namevar.find("v2");
		if(found!=namevar.end())varval[found->second]=&v2;
        v2=0;
		//end{generated}
	    		
	};
	virtual void pastedAction()
	{
		//user's code snippet : pasted verbatim
		cout<<endl<<"["<<v1<<" , "<< v2 << "]";
	}

    virtual void recurseBindings(map<Variable*,vector<int>*> &tuple)
	{
		if(tuple.empty())
		{
			pastedAction();
			return;
		}
		map<Variable*,vector<int>*> tupleHere=tuple;
		map<Variable*,vector<int>*>::iterator thisone=tuple.begin();
		tupleHere.erase(tupleHere.begin());
		Variable * thisvar=thisone->first;
		vector<int>::iterator valiter;
		for(valiter=thisone->second->begin();valiter!=thisone->second->end();++valiter){
			map<Variable*,int*>::iterator valpfound=varval.find(thisvar); 
			if(valpfound!=varval.end())*(valpfound->second)=*valiter;
			recurseBindings(tupleHere);
		}
	}

};
void reltest1()
{
	cout<<endl<<"Test 1: Transitive Closure "<<endl;
    Domain *dnet=new Domain("net",60);
	Domain  *dport=new Domain("port",60);
	Variable *n1= new Variable("n1", dnet);
	Variable *n2= new Variable("n2", dnet);
	Variable * n3=new Variable("n3",dnet);
	Variable * p1=new Variable("p1",dport);
	Variable * p2=new Variable("p2",dport);
    
        Relation * r= new Relation(n1,p1,n2,p2,NULL);
        cout<<"\n-------------------------------\n";
	    r->addTuple(51,22,53,24);
 	    r->addTuple(53,24,55,27);
        r->addTuple(53,24,59,32);
        r->addTuple(59,32,41,21);
        r->print(stdout);
        cout<<"\n-------------------------------\n";
	
        bool retcode=r->transitiveClosure();
        if(retcode) cout<<"Self join succeeded"   <<endl;
        else cout << "Self join failed"<<endl;
	    r->print(stdout);
		cout<<"\nnum:"<<r->numTuples()<<endl;
}

void reltest2()
{
   //
	cout<<endl<<"Test 2: Universal Quantification"<<endl;
   Domain * d=new Domain("Generic",30);
   Variable * v1= new Variable("v1",d);
   Variable * v2= new Variable("v2",d);
   Relation * r1=new Relation(v1,v2,NULL);
   Relation * r2=new Relation(v1,NULL);
   r1->addTuple(1,2);
   r1->addTuple(2,2);
   r1->addTuple(1,6);
   r1->addTuple(2,6);
   r2->addTuple(1);
   r2->addTuple(2);

   r1->print(stdout);
   r1->quantifyForall(r2,v1,NULL);
   r1->print(stdout);
   cout<<"\nnum :"<<r1->numTuples()<<endl;

}

void reltest3()
{
   //
	cout<<endl<<"Test 3: Existential Quantification"<<endl;
   Domain * d=new Domain("Generic",10000);
   Variable * v1= new Variable("v1",d);
   Variable * v2= new Variable("v2",d);
   Relation * r1=new Relation(v1,v2,NULL);
   Relation * r2=new Relation(v1,NULL);
   r1->addTuple(1000,6000);
   r1->addTuple(2000,8000);
   r1->addTuple(1000,6000);
   r1->addTuple(2000,3000);
   r1->addTuple(9000,1234);

   r2->addTuple(1000);
   r2->addTuple(2000);

   r1->print(stdout);
   r1->quantifyExists(r2,v1,NULL);
   r1->print(stdout);
   cout<<"\nnum :"<<r1->numTuples()<<endl;

}

void reltest4()
{
   //
	cout<<endl<<"Test 5: Explicit Traversal"<<endl;
   Domain * d=new Domain("Generic",10000);
   Variable * v1= new Variable("v1",d);
   Variable * v2= new Variable("v2",d);
   Relation * r1=new Relation(v1,v2,NULL);
   Relation * r2=new Relation(v1,NULL);
   r1->addTuple(1000,6000);
   r1->addTuple(2000,8000);
   r1->addTuple(1000,6000);
   r1->addTuple(2000,3000);
   r1->addTuple(9000,1234);
   r1->addTuple(9000,5678);
   r1->addTuple(9000,6789);

   r2->addTuple(1000);
   r2->addTuple(2000);

   CB1 cb(r1);
   r1->print(stdout);
   r1->traverse(cb);

   //r1->quantifyExists(r2,v1,NULL);
   //r1->print(stdout);

}


void reltest()
{

   	bdd_init(1000000,1000000);
    reltest1();
	reltest2();
	reltest3();
	reltest4();

}



