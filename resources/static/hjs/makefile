# COMPILER = ${UHC} --import-path=${UHC_JSCRIPT} --import-path=${UHC_NANOPROLOG} --import-path=${UHC_UU_TC} -tjs --no-recomp --no-hi-check -O,2 # --dump-core-stages=1
COMPILER = ${UHC} --import-path=${UHC_JSCRIPT} --import-path=${UHC_NANOPROLOG} --import-path=${UHC_UU_TC} -tjs -O,2 # --no-recomp --no-hi-check --dump-core-stages=1

all: build

build: webworker
	${COMPILER} jcu.hs

webworker: 
	${COMPILER} Worker.hs
	rm Worker.html

	
infinite: 
	${COMPILER} infinite.hs

testcase: testcases/*.hs
	cd testcases && ${COMPILER} alert.hs
	
test:
	echo $(GHC_OPTS)

.PHONY clean-core:
	rm `find . -d -name "*.core*"`
	rm `find ${LANGUAGE_DIR} -d -name "*.core*"`