rscript = Rscript --no-save --no-restore
unexport R_PROFILE_USER

# Helper functions for a recursive wildcard function.
match_files = $(filter $(subst *,%,$2),$1)
filter_out_dirs = $(filter-out %/,$(foreach f,$1,$(wildcard $f/)))
rec_find = $(foreach f,$(wildcard ${1:=/*}),$(call filter_out_dirs,$(call rec_find,$f,$2) $(call match_files,$f,$2)))

r_source_files = $(wildcard R/*.r)
c_source_files = $(wildcard src/*.c src/*.h)

vignette_files = $(call rec_find,vignettes,*)

rmd_files = $(wildcard vignettes/*.rmd)
knit_results = $(patsubst vignettes/%.rmd,doc/%.md,${rmd_files})

pkg_bundle_name := $(shell ${rscript} --vanilla -e 'cat(sprintf("%s.tar.gz\n", paste(read.dcf("DESCRIPTION")[1L, c("Package", "Version")], collapse = "_")))')

cran-tmpdir = tmp.cran

favicons_small = $(addprefix pkgdown/favicon/,$(addprefix favicon-,16x16.png 32x32.png))

favicons_large = $(addprefix pkgdown/favicon/,\
	$(addsuffix .png,$(addprefix apple-touch-icon-,60x60 76x76 120x120 152x152)))

favicon_default = pkgdown/favicon/apple-touch-icon.png

favicons = ${favicons_small} ${favicons_large} ${favicon_default}

inkscape = $(shell command -v inkscape || echo /Applications/Inkscape.app/Contents/MacOS/inkscape)

.PHONY: test
## Run unit tests
test: documentation
	${rscript} -e "devtools::test(export_all = FALSE)"

## Run a single, named unit test
/test-%: documentation
	${rscript} -e "devtools::test(filter = '$*', export_all = FALSE)"

.PHONY: check
## Run R CMD check
check: documentation
	ret=0; \
		for rule in scripts/check_rule_*; do \
			if ! $$rule .; then ret=1; fi \
		done; \
		mkdir -p check; \
		${rscript} -e "devtools::check(check_dir = 'check')"; \
		check=$$?; \
		let ret='ret | check'; \
		exit $$ret

.PHONY: site
## Create package website
site: README.md NAMESPACE NEWS.md ${favicons}
	${rscript} -e "pkgdown::build_site(new_process = FALSE)"
	scripts/copy-vignette-extra-files . docs/articles 2>/dev/null \
	|| scripts/copy-vignette-extra-files . docs/dev/articles \

.PHONY: dev-site
## Create package website [dev mode]
dev-site: README.md NAMESPACE
	${rscript} -e "pkgdown::build_site(devel = TRUE)"

## Create just the specified article for the website
/article-%:
	${rscript} -e "pkgdown::build_article('$*')"

## Create just the references for the website
reference: documentation
	${rscript} -e "pkgdown::build_reference()"

# FIXME: Old reason for building everything twice no longer exists; do we need
# both `all-vignette` and `knit-all` rules?
.PHONY: all-vignettes
## Compile all vignettes and other R Markdown articles
all-vignettes: Meta/vignette.rds

Meta/vignette.rds: DESCRIPTION NAMESPACE ${r_source_files} ${vignette_files}
	${rscript} -e "devtools::build_vignettes(dependencies = TRUE)"

.PHONY: knit-all
## Compile R markdown articles and move files to the documentation directory
knit-all: ${knit_results} | doc

doc/%.md: vignettes/%.rmd DESCRIPTION NAMESPACE ${r_source_files} | doc
	${rscript} -e "rmarkdown::render('$<', output_format = 'md_document', output_file = '${@F}', output_dir = '${@D}')"

.PHONY: documentation
## Compile the in-line package documentation
documentation: NAMESPACE

# Delete NAMESPACE on compilation failure; otherwise rerunning the rule won’t do
# anything.
NAMESPACE: ${r_source_files} ${c_source_files} DESCRIPTION
	echo >NAMESPACE '# Generated by roxygen2: do not edit by hand' # Workaround for bug #1070 in roxygen2 7.1.0
	${rscript} -e "devtools::document()" || { ${RM} $@; exit 1; }

README.md: README.rmd NAMESPACE DESCRIPTION man/figures/logo.png
	${rscript} -e "devtools::load_all(export_all = FALSE); knitr::knit('$<')"

man/figures/logo.png: figures/logo.svg
	${inkscape} -w 240 --export-filename ${@:.png=.tmp.png} $<
	pngcrush ${@:.png=.tmp.png} $@
	${RM} ${@:.png=.tmp.png}

.PHONY: build
## Build the package tar.gz bundle
build: ${pkg_bundle_name}

${pkg_bundle_name}: DESCRIPTION NAMESPACE ${r_source_files}
	R CMD build .

.PHONY: build-cran
## Bundle the package with static vignette sources for submission to CRAN
build-cran:
	@git diff-index --quiet HEAD || { printf 'ERROR: Uncommitted changes found!\n'; exit 1; }
	${RM} -r ${cran-tmpdir} \
	&& git clone . ${cran-tmpdir} \
	&& sed "s/@YEAR@/$$(date +%Y)/" cran/LICENSE >${cran-tmpdir}/LICENSE \
	&& echo 'renv::load("${PWD}")' >${cran-tmpdir}/.Rprofile \
	&& ${MAKE} -C ${cran-tmpdir} knit-all \
	&& scripts/precompile-vignettes ${cran-tmpdir} \
	&& ${MAKE} -C ${cran-tmpdir} build \
	&& mv ${cran-tmpdir}/${pkg_bundle_name} . \
	&& ${RM} -r ${cran-tmpdir}

.PHONY: favicons
## Generate the documentation site favicons
favicons: ${favicons}

export-favicon = \
	@sz=$$(sed 's/.*x\([[:digit:]]*\)\.png/\1/' <<<"$@") \
	&& set -x; \
	${inkscape} -w $$sz -h $$sz --export-area $1 --export-filename=${@D}/tmp-${@F} $< \
	&& pngcrush -q ${@D}/tmp-${@F} $@ && rm ${@D}/tmp-${@F}

${favicons_small}: figures/logo.svg | pkgdown/favicon
	$(call export-favicon,-11:1000:181:1192)

${favicons_large}: figures/logo.svg | pkgdown/favicon
	$(call export-favicon,-51:0:711:760)

${favicon_default}: figures/logo.svg | pkgdown/favicon
	${inkscape} -w 180 -h 180 --export-area -51:0:711:760 --export-filename=${@D}/tmp-${@F} $<
	pngcrush -q ${@D}/tmp-${@F} $@ && rm ${@D}/tmp-${@F}

.PHONY: lint
## Link the package source
lint:
	${rscript} -e "lintr::lint_package('.')"

doc pkgdown/favicon:
	mkdir -p $@

## Clean up all build files
cleanall:
	${RM} -r doc docs Meta
	${RM} man/*.Rd
	${RM} NAMESPACE
	${RM} src/*.o src/*.so

.DEFAULT_GOAL := show-help
# See <https://github.com/klmr/maketools/tree/master/doc>.
.PHONY: show-help
show-help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)";echo;sed -ne"/^## /{h;s/.*//;:d" -e"H;n;s/^## //;td" -e"s/:.*//;G;s/\\n## /---/;s/\\n/ /g;p;}" ${MAKEFILE_LIST}|LC_ALL='C' sort -f|awk -F --- -v n=$$(tput cols) -v i=19 -v a="$$(tput setaf 6)" -v z="$$(tput sgr0)" '{printf"%s%*s%s ",a,-i,$$1,z;m=split($$2,w," ");l=n-i;for(j=1;j<=m;j++){l-=length(w[j])+1;if(l<= 0){l=n-i-length(w[j])-1;printf"\n%*s ",-i," ";}printf"%s ",w[j];}printf"\n";}'|more $$(test $$(uname) = Darwin && echo \-Xr)
