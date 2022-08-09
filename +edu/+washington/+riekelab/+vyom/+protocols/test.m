contrasts = [1 2 3 4 5];
tol=0.0001;              
idx_c=1;
for idx_e=1:100
    c = contrasts(idx_c);
    test_c = contrasts(abs(contrasts-c)>tol);
    idx_ct = mod(idx_e, length(test_c))+1;
    ct = test_c(idx_ct);
    if mod(idx_e,length(test_c))==0
     idx_c = mod(idx_c, length(contrasts))+1; 
    end
    disp(c);
    disp(ct);

end