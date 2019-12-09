/* turn on graphics */
ods graphics;

/* create library */
libname winedata '/folders/myfolders/wine-data';

/* import files */
%web_drop_table(WORK.IMPORT);
filename one30 "/folders/myfolders/winemag-data-130k-v2.csv";
proc import datafile=one30
	dbms=csv
	out=import;
	getnames=yes;
	guessingrows=100;
run;
proc contents data=import;
run;
%web_open_table(WORK.IMPORT);

%web_drop_table(WORK.IMPORT1);
filename one50 "/folders/myfolders/winemag-data_first150k.csv";
proc import datafile=one50
	dbms=csv
	out=import1;
	getnames=yes;
	guessingrows=100;
run;
proc contents data=import1;
run;
%web_open_table(WORK.IMPORT1);

/* create master dataset */
data winedata.master(drop= taster_name taster_twitter_handle title var1) replace;
	length country $9;
	set import1 import;
run;

/* view dataset info */
proc contents data=winedata.master;
run;

proc means data=winedata.master nmiss;
run;

/* impute values for missing data */
proc stdize data=winedata.master
  reponly  
  method=median  
  out=winedata.master_imp;  
  var price;  
run;

/* clean dataset, only points above 80 and not missing */
data winedata.data_clean;
	set winedata.master_imp;
	where points is not missing
	and points >= 80;
run;

/* sort by points */
proc sort data=winedata.data_clean out=wine_sort;  
	by points;  
run;

/* create training and validation datasets 60/40 */
proc surveyselect data=wine_sort 
	method=srs 
	samprate= .60 
	out=wine_select 
	seed= 2222
	outall;  
	strata points;
run;

data winedata.train;  
	set wine_select;  
	if selected= 1;
	drop selected SamplingWeight SelectionProb;
run;

data winedata.validate;  
	set wine_select;  
	if selected= 0;
	drop selected SamplingWeight SelectionProb;
run;

/* box plots by country */
proc sgplot data=winedata.train;
	vbox points / category=country connect=mean;
run;

/* scatterplot by price */
proc sgscatter data=winedata.train;
	plot points*price / reg;
run;

/* test for ANOVA/homogeneity of variance - country */
proc glm data=winedata.train plots=diagnostics;
	class country;
	model points=country;
	means country / hovtest=levene;
run; quit;

/* since homogeneity failed, kruskal wallis run */
proc npar1way data=winedata.train;
	class country;
	var points;
run;

/* post hoc tests - country */
proc glm data=winedata.train;
	class country;
	model points = country;
	lsmeans country / pdiff=all adjust=tukey;
run; quit;

/* test for ANOVA/homogeneity of variance - variety */
proc glm data=winedata.train plots=diagnostics;
	class variety;
	model points=variety;
	means variety / hovtest=levene;
run; quit;

/* since homogeneity failed, kruskal wallis run */
proc npar1way data=winedata.train;
	class variety;
	var points;
run;

/* Pearson correlation - price */
proc corr data=winedata.train;
	var price;
	with points;
run;

/* create model dep. var = points, ind. vars = country, price, variety */
proc glm data=winedata.train;
	class country variety;
	model points= country price variety;
	store winedata.score;
run; quit;

/* score model on validation data */
proc plm restore=winedata.score;
	score data=winedata.validate out=validated;
run;

/* turn off graphics */
ods graphics off;

  