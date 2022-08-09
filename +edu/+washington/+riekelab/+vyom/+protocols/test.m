contrasts = [1 2 3 4 5];
tol=0.0001;              
idx_c=1;
for idx_e=1:100
    c = contrasts(idx_c);
    test_c = contrasts(abs(contrasts-c)>tol);
    ct = test_c(mod(idx_e+1, length(test_c))+1);
    if mod(idx_e,length(test_c))==0
     idx_c = mod(idx_c+1, length(contrasts))+1; 
    end
    disp(c);
    disp(ct);

end