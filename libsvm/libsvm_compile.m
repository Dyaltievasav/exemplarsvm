% add -largeArrayDims on 64-bit machines

mex -O -c svm.cpp
mex -O -c svm_model_matlab.c
mex -O libsvmtrain.c svm.o svm_model_matlab.o

%These files are not used
%mex -O svmpredict.c svm.obj svm_model_matlab.obj
%mex -O libsvmread.c
%mex -O libsvmwrite.c