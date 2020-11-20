#!/usr/bin/env bash
for lst in `find . -name '-tmp*.lst'`; do
  rm -f $lst
done

for lst in `find . -name '..*.lst'`; do
  rm -f $lst
done
