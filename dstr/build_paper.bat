@echo off
setlocal

xelatex dstr_paper.tex
if errorlevel 1 exit /b %errorlevel%

bibtex dstr_paper
if errorlevel 1 exit /b %errorlevel%

xelatex dstr_paper.tex
if errorlevel 1 exit /b %errorlevel%

xelatex dstr_paper.tex
if errorlevel 1 exit /b %errorlevel%
