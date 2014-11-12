.PHONY: vignettes
# Additionally build the *.md file, and copy all files
vignettes: knit_all
	Rscript --no-save --no-restore -e "library(knitr); build_vignettes()"

rmd_files=$(wildcard vignettes/*.rmd)
knit_results=$(patsubst vignettes/%.rmd,inst/doc/%.md,${rmd_files})

.PHONY: knit_all
knit_all: inst/doc ${knit_results}
	cp -r vignettes/* inst/doc/

inst/doc:
	mkdir -p $@

inst/doc/%.md: vignettes/%.rmd
	Rscript --no-save --no-restore -e "library(knitr); knit('$<', '$@')"

.PHONY: documentation
documentation:
	Rscript --no-save --no-restore -e "document()"
