#!/bin/bash
for i in */*.strings; do
	scp $i ipod:
	ssh ipod plutil -c xml1 Localizable.strings
	scp ipod:Localizable.strings $i
done
