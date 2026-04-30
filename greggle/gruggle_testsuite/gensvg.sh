ls -1 *.golden | xargs -I{} dot {} -Tsvg -o {}.svg
ls -1 *.dot | xargs -I{} dot {} -Tsvg -o {}.svg
ls -1 *.golden | xargs -I{} dot {} -Tpdf -o {}.pdf
ls -1 *.dot | xargs -I{} dot {} -Tpdf -o {}.pdf

