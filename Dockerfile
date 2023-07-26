FROM public.ecr.aws/shogo82148/p5-aws-lambda:base-5.36.al2

RUN yum install -y awscli bzip2 gcc gcc-c++ git libcurl-devel make mariadb-devel openssl-devel tar unzip wget which zlib-devel

ENV OPT /opt/vep
ENV OPT_SRC $OPT/src
# ENV HTSLIB_DIR $OPT_SRC/htslib
ENV HTSLIB_VERSION=1.17
ENV HTSLIB_CONFIGURE_OPTIONS="--enable-s3 --disable-bz2 --disable-lzma"
ENV ENSEMBL_VERSION 109
ENV BRANCH release/${ENSEMBL_VERSION}

WORKDIR $OPT_SRC

RUN wget -q "https://raw.githubusercontent.com/Ensembl/ensembl/$BRANCH/cpanfile" -O "ensembl_cpanfile" && \
    # Clone ensembl-vep git repository
    git clone $BRANCH_OPT --depth 1 https://github.com/Ensembl/ensembl-vep.git && chmod u+x ensembl-vep/*.pl && \
    # Clone ensembl-variation git repository
    git clone $BRANCH_OPT --depth 1 https://github.com/Ensembl/ensembl-variation.git && \
    # Download ensembl-xs - it contains compiled versions of certain key subroutines used in VEP
    wget https://github.com/Ensembl/ensembl-xs/archive/2.3.2.zip -O ensembl-xs.zip && \
    unzip -q ensembl-xs.zip && mv ensembl-xs-2.3.2 ensembl-xs && rm -rf ensembl-xs.zip && \
    # Clone/Download other repositories: bioperl-live is needed so the cpanm dependencies installation from the ensembl-vep/cpanfile file takes less disk space
    git clone --branch release-1-6-924 --depth 1 https://github.com/bioperl/bioperl-live.git && \
    git clone --branch release/v2.11 --depth 1 https://github.com/Ensembl/Bio-HTS.git && \
    # Only keep the bioperl-live "Bio" library
    mv bioperl-live bioperl-live_bak && mkdir bioperl-live && mv bioperl-live_bak/Bio bioperl-live/ && rm -rf bioperl-live_bak && \
    ## A lot of cleanup on the imported libraries, in order to reduce the docker image ##
    rm -rf Bio-HTS/.??* Bio-HTS/Changes Bio-HTS/DISCLAIMER Bio-HTS/MANIFEST* Bio-HTS/README Bio-HTS/scripts Bio-HTS/t Bio-HTS/travisci \
           ensembl-vep/.??* ensembl-vep/docker \
           ensembl-xs/.??* ensembl-xs/TODO ensembl-xs/Changes ensembl-xs/INSTALL ensembl-xs/MANIFEST ensembl-xs/README ensembl-xs/t ensembl-xs/travisci \
           htslib/.??* htslib/INSTALL htslib/NEWS htslib/README* htslib/test

# Install htslib binaries (for 'bgzip' and 'tabix')
WORKDIR $OPT_SRC
RUN wget https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2 && \
    tar xjf htslib-${HTSLIB_VERSION}.tar.bz2 && \
    cd htslib-${HTSLIB_VERSION} && \
    ./configure ${HTSLIB_CONFIGURE_OPTIONS} && \
    make && make install && \
    cd ../ && \
    rm -rf htslib-${HTSLIB_VERSION} htslib-${HTSLIB_VERSION}.tar.bz2
ENV HTSLIB_DIR=/usr/local/lib
ENV HTSLIB_INCLUDE_DIR=/usr/local/include
ENV LD_LIBRARY_PATH=/usr/local/lib

# Install ensembl-xs, faster run using re-implementation in C of some of the Perl subroutines
WORKDIR $OPT_SRC/ensembl-xs
RUN perl Makefile.PL && make && make install && rm -f Makefile* cpanfile

# install Bio-HTS
ENV PERL5LIB_TMP $PERL5LIB:$OPT_SRC/ensembl-vep:$OPT_SRC/ensembl-vep/modules
ENV PERL5LIB $PERL5LIB_TMP:$OPT_SRC/bioperl-live
WORKDIR $OPT_SRC/Bio-HTS
RUN perl Build.PL && \
	./Build && \
	./Build test && \
	./Build install && \
	rm -rf cpanfile Build.PL Build _build INSTALL.pl

# Install/compile more libraries
WORKDIR $OPT_SRC
RUN egrep -v "BigFile" ensembl-vep/cpanfile > ensembl-vep/cpanfile_tmp && mv ensembl-vep/cpanfile_tmp ensembl-vep/cpanfile
RUN cpanm --installdeps --with-recommends --notest --cpanfile ensembl_cpanfile . && \
    cpanm --installdeps --with-recommends --notest --cpanfile ensembl-vep/cpanfile . && \
    # Delete bioperl and cpanfiles after the cpanm installs as bioperl will be reinstalled by the INSTALL.pl script
    rm -rf bioperl-live ensembl_cpanfile ensembl-vep/cpanfile

# Install vep-lambda requirements
COPY cpanfile $OPT_SRC/vep_lambda_cpanfile
RUN cpanm --installdeps --cpanfile $OPT_SRC/vep_lambda_cpanfile .

# Remove CPAN cache
RUN rm -rf /root/.cpanm

# Setup Docker environment for when users run VEP and INSTALL.pl in Docker image:
#   - skip VEP updates in INSTALL.pl
ENV VEP_NO_UPDATE 1
#   - avoid Faidx/HTSLIB installation in INSTALL.pl
ENV VEP_NO_HTSLIB 1
#   - skip plugin installation in INSTALL.pl
ENV VEP_NO_PLUGINS 1
#   - set plugins directory for VEP and INSTALL.pl
ENV VEP_DIR_PLUGINS /plugins
ENV VEP_PLUGINSDIR $VEP_DIR_PLUGINS
WORKDIR $VEP_DIR_PLUGINS

WORKDIR $OPT_SRC/ensembl-vep

# Install Ensembl API and plugins
RUN ./INSTALL.pl --auto ap --plugins all --pluginsdir $VEP_DIR_PLUGINS --no_update --no_htslib --no_test && \
    # Remove the ensemb-vep tests and travis
    rm -rf t travisci .travis.yml

COPY TabixCache.pm $VEP_DIR_PLUGINS/
COPY chr_synonyms.txt $OPT_SRC/
COPY handler.pl /var/task/
COPY FastaSequence.pm ${OPT_SRC}/ensembl-vep/Bio/EnsEMBL/Variation/Utils/FastaSequence.pm
ENV HOME /root
CMD [ "handler.handle" ]