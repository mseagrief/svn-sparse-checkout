svn-sparse-checkout
===================

Ruby script to automate creating complex sparse checkouts from subversion with versioned configuration files

Details
=======

See http://seagrief.co.uk/2011/02/subversion-sparse-checkout-tool/ for a detailed explaination of the why and wherefore of this script.

Syntax
======

.yaml configuration files are expected to exist in a folder called sparse that exists at the root directory of a project (e.g. trunk/sparse or branches/feature-x/sparse).

```
 description: Everything needed to compile and build
 base: build/
 
 files:
     all:
         - build/thirdparty/*
         - build/code/buildtools/*
         - build/buildtools/@
         - build/plugins/*
     linux:
         - build/libs/linux/*
     windows:
         - build/libs/windows/*
```
