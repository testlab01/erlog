%% Copyright (c) 2013 Robert Virding
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%% File    : erlog_lib_lists.erl
%% Author  : Robert Virding
%% Purpose : Standard Erlog lists library.
%% 
%% This is a standard lists library for Erlog. Everything here is
%% pretty basic and common to most Prologs. We are experimenting here
%% and some predicates are compiled. We only get a small benefit when
%% only implementing indexing on the first argument.

-module(erlog_lib_lists).

-include("erlog_int.hrl").

%% Main interface functions.
-export([load/1]).

%% Library functions.
-export([length_2/3,append_3/3,insert_3/3,member_2/3,memberchk_2/3,
	 reverse_2/3,sort_2/3]).

%%-compile(export_all).

-import(lists, [map/2,foldl/3]).

%% We use these a lot so we import them for cleaner code.
-import(erlog_int, [prove_body/2,unify_prove_body/4,unify_prove_body/6,fail/1,
		    add_binding/3,make_var_list/2,
		    deref/2,dderef/2,dderef_list/2,unify/3,
		    term_instance/2,
		    add_built_in/2,add_compiled_proc/4,
		    asserta_clause/2,assertz_clause/2]).

%% load(Database) -> Database.
%%  Assert predicates into the database.

load(Db0) ->
    %% Compiled common list library.
    Db1 = foldl(fun ({Head,M,F}, Db) ->
			add_compiled_proc(Head, M, F, Db) end, Db0,
		[
		 {{length,2},?MODULE,length_2},
		 {{append,3},?MODULE,append_3},
		 {{insert,3},?MODULE,insert_3},
		 {{member,2},?MODULE,member_2},
		 {{memberchk,2},?MODULE,memberchk_2},
		 {{reverse,2},?MODULE,reverse_2},
		 {{sort,2},?MODULE,sort_2}
		]),
    %% Finally interpreted common list library.
    foldl(fun (Clause, Db) -> assertz_clause(Clause, Db) end, Db1,
	  [
	   %% insert(L, X, [X|L]). insert([H|L], X, [H|L1]) :- insert(L, X, L1).
	   %% delete([X|L], X, L). delete([H|L], X, [H|L1]) :- delete(L, X, L1).
	   {':-',{delete,{1},{2},{3}},{insert,{3},{2},{1}}},
	   %% last(List, Last) :- append(_, [Last], List).
	   {':-',{last,{1},{2}},{append,{3},[{2}],{1}}},
	   %% perm([], []).
	   %% perm([X|Xs], Ys1) :- perm(Xs, Ys), insert(Ys, X, Ys1).
	   {perm,[],[]},
	   {':-',{perm,[{1}|{2}],{3}},{',',{perm,{2},{4}},{insert,{4},{1},{3}}}}
	  ]).

%% length_2(Head, NextGoal, State) -> void.
%% length(L, N) :- integer(N), !, N >= 0, '$make_list'(N, L).
%% length(L, N) :- '$length'(L, 0, N).
%% '$length'([], N, N).
%% '$length'([_|L], M, N) :- M1 is M + 1, '$length'(L, M1, N).
%% '$make_list'(0, []) :- !.
%% '$make_list'(N, [_|L]) :- N1 is N - 1, '$make_list'(N1, L).

length_2({length,L,N0}, Next, #est{bs=Bs}=St) ->
    case deref(N0, Bs) of				%Export N1
	N1 when is_integer(N1) ->
	    if N1 >= 0 -> make_list(N1, L, Next, St);
	       true -> fail(St)
	    end;
	{_}=N1 ->
	    length_3(L, 0, N1, Next, St);
	N1 ->
	    erlog_int:type_error(integer, N1, St)
    end.

length_3(L0, M, N, Next, #est{cps=Cps,bs=Bs0,vn=Vn}=St) ->
    case deref(L0, Bs0) of
	[] -> unify_prove_body(N, M, Next, St); 
	[_|T] -> length_3(T, M+1, N, Next, St);
	{_}=L1 ->
	    FailFun = fun (Lcp, Lcps, Lst) ->
			      fail_length_3(Lcp, Lcps, Lst, L1, M, N)
		      end,
	    Cp = #cp{type=compiled,data=FailFun,next=Next,bs=Bs0,vn=Vn},
	    Bs1 = add_binding(L1, [], Bs0),
	    unify_prove_body(N, M, Next, St#est{cps=[Cp|Cps],bs=Bs1});
	Other ->
	    erlog_int:type_error(list, Other, St)
    end.

fail_length_3(#cp{next=Next,bs=Bs0,vn=Vn}, Cps, St, L, M, N) ->
    H = {Vn},
    T = {Vn+1},
    Bs1 = add_binding(L, [H|T], Bs0),
    length_3(T, M+1, N, Next, St#est{cps=Cps,bs=Bs1,vn=Vn+2}).

make_list(0, L, Next, St) ->
    unify_prove_body(L, [], Next, St);
make_list(N, L0, Next, #est{bs=Bs0,vn=Vn}=St) ->
    case deref(L0, Bs0) of
	[] -> fail(St);				%We know N /= 0
	[_|T] ->				%Keep stepping down the list
	    make_list(N-1, T, Next, St);
	{_}=L1 ->				%Just make a list of the rest
	    List = make_var_list(N, Vn),
	    Bs1 = add_binding(L1, List, Bs0),
	    prove_body(Next, St#est{bs=Bs1,vn=Vn+N});
	Other ->
	    erlog_int:type_error(list, Other, St)
    end.

%% append_3(Head, NextGoal, State) -> void.
%% append([], L, L).
%% append([H|T], L, [H|L1]) :- append(T, L, L1).
%%  Here we attempt to compile indexing in the first argument.

append_3({append,A1,L,A3}, Next0, #est{cps=Cps,bs=Bs0,vn=Vn}=St) ->
    case deref(A1, Bs0) of
	[] ->					%Cannot backtrack
	    unify_prove_body(L, A3, Next0, St);
	[H|T] ->				%Cannot backtrack
	    L1 = {Vn},
	    Next1 = [{append,T,L,L1}|Next0],
	    unify_prove_body(A3, [H|L1], Next1, St#est{vn=Vn+1});
	{_}=Var ->				%This can backtrack
	    FailFun = fun (LCp, LCps, Lst) ->
			      fail_append_3(LCp, LCps, Lst, Var, L, A3)
		      end,
	    Cp = #cp{type=compiled,data=FailFun,next=Next0,bs=Bs0,vn=Vn},
	    Bs1 = add_binding(Var, [], Bs0),
	    unify_prove_body(L, A3, Next0, St#est{cps=[Cp|Cps],bs=Bs1});
	_ -> fail(St)				%Will fail here!
    end.

fail_append_3(#cp{next=Next0,bs=Bs0,vn=Vn}, Cps, St, A1, L, A3) ->
    H = {Vn},
    T = {Vn+1},
    L1 = {Vn+2},
    Bs1 = add_binding(A1, [H|T], Bs0),		%A1 always a variable here.
    Next1 = [{append,T,L,L1}|Next0],
    unify_prove_body(A3, [H|L1], Next1, St#est{cps=Cps,bs=Bs1,vn=Vn+3}).

%% insert_3(Head, NextGoal, State) -> void.
%% insert(L, X, [X|L]).
%% insert([H|L], X, [H|L1]) :- insert(L, X, L1).

insert_3({insert,A1,A2,A3}, Next, #est{cps=Cps,bs=Bs,vn=Vn}=St) ->
    FailFun = fun (LCp, LCps, Lst) ->
		      fail_insert_3(LCp, LCps, Lst, A1, A2, A3)
	      end,
    Cp = #cp{type=compiled,data=FailFun,next=Next,bs=Bs,vn=Vn},
    unify_prove_body(A3, [A2|A1], Next, St#est{cps=[Cp|Cps]}).

fail_insert_3(#cp{next=Next0,bs=Bs,vn=Vn}, Cps, St, A1, X, A3) ->
    H = {Vn},
    L = {Vn+1},
    L1 = {Vn+2},
    Next1 = [{insert,L,X,L1}|Next0],
    unify_prove_body(A1, [H|L], A3, [H|L1], Next1, St#est{cps=Cps,bs=Bs,vn=Vn+3}).

%% member_2(Head, NextGoal, State) -> void.
%% member(X, [X|_]).
%% member(X, [_|T]) :- member(X, T).

member_2({member,A1,A2}, Next, #est{cps=Cps,bs=Bs,vn=Vn}=St) ->
    FailFun = fun (LCp, LCps, Lst) ->
		      fail_member_2(LCp, LCps, Lst, A1, A2)
	      end,
    Cp = #cp{type=compiled,data=FailFun,next=Next,bs=Bs,vn=Vn},
    T = {Vn},
    unify_prove_body(A2, [A1|T], Next, St#est{cps=[Cp|Cps],vn=Vn+1}).

fail_member_2(#cp{next=Next0,bs=Bs,vn=Vn}, Cps, St, A1, A2) ->
    H = {Vn},
    T = {Vn+1},
    Next1 = [{member,A1,T}|Next0],
    unify_prove_body(A2, [H|T], Next1, St#est{cps=Cps,bs=Bs,vn=Vn+2}).

%% memberchk_2(Head, NextGoal, State) -> void.
%% memberchk(X, [X|_]) :- !.
%% memberchk(X, [_|T]) :- memberchk(X, T).
%%  We don't build the list and we never backtrack so we can be smart
%%  and match directly. Should we give a type error?

memberchk_2({memberchk,A1,A2}, Next, #est{bs=Bs0}=St) ->
    case deref(A2, Bs0) of
	[H|T] ->
	    case unify(A1, H, Bs0) of
		{succeed,Bs1} ->
		    prove_body(Next, St#est{bs=Bs1});
		fail ->
		    memberchk_2({memberchk,A1,T}, Next, St)
	    end;
	{_} -> erlog_int:instantiation_error(St);
	_ -> fail(St)
    end.

%% reverse_2(Head, NextGoal, State) -> void.
%% reverse([], []).
%% reverse([H|L1], L) :- reverse(L1, L2), append(L2, [H], L).
%%  Here we attempt to compile indexing in the first argument.

reverse_2({reverse,A1,A2}, Next0, #est{cps=Cps,bs=Bs0,vn=Vn}=St) ->
    case deref(A1, Bs0) of
	[] ->
	    unify_prove_body(A2, [], Next0, St);
	[H|T] ->
	    L = {Vn},
	    L1 = A2,
	    %% Naive straight expansion of body.
	    %%Next1 = [{reverse,T,L},{append,L,[H],L1}|Next0],
	    %%prove_body(Next1, Cps, Bs0, Vn+1, Db);
	    %% Smarter direct calling of local function.
	    Next1 = [{append,L,[H],L1}|Next0],
	    reverse_2({reverse,T,L}, Next1, St#est{vn=Vn+1});
	{_}=Var ->
	    FailFun = fun (LCp, LCps, Lst) ->
			      fail_reverse_2(LCp, LCps, Lst, Var, A2)
		      end,
	    Cp = #cp{type=compiled,data=FailFun,next=Next0,bs=Bs0,vn=Vn},
	    Bs1 = add_binding(Var, [], Bs0),
	    unify_prove_body(A2, [], Next0, St#est{cps=[Cp|Cps],bs=Bs1});
	_ -> fail(St)				%Will fail here!
    end.

fail_reverse_2(#cp{next=Next,bs=Bs0,vn=Vn}, Cps, St, A1, A2) ->
    H = {Vn},
    T = {Vn+1},
    L1 = A2,
    L = {Vn+2},
    Bs1 = add_binding(A1, [H|T], Bs0),
    %%Next1 = [{reverse,T,L},{apperse,L,[H],L1}|Next],
    %%prove_body(Next1, Cps, Bs1, Vn+3, Db).
    Next1 = [{append,L,[H],L1}|Next],
    reverse_2({reverse,T,L}, Next1, St#est{cps=Cps,bs=Bs1,vn=Vn+3}).

%% sort_2(Head, NextGoal, State) -> void.
%% sort(List, SortedList).

sort_2({sort,L0,S}, Next, #est{bs=Bs}=St) ->
    %% This may throw an erlog error, we don't catch it here.
    L1 = lists:usort(dderef_list(L0, Bs)),
    unify_prove_body(S, L1, Next, St).
