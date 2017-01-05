2017-01-05 児玉  

### BioProject example XML files  

bioproject_example_files  

[xsd](https://github.com/ddbj/docs/blob/master/bioproject/xsd/)

```
xmllint PSUB006794.xml --noout --schema bioproject/xsd/Package.xsd
```

* [Umbrella BioProject](http://trace.ddbj.nig.ac.jp/bioproject/submission.html#プライマリープロジェクトとアンブレラプロジェクト)
* アクセッション番号未発行の XML はエラーになります  

### DRA example XML files  

dra_example_files  

[xsd](https://github.com/ddbj/docs/tree/master/dra/xsd/1-5)

```
xmllint afujiyam-0022.submission.xml --noout --schema dra/xsd/1-5/SRA.submission.xsd
xmllint afujiyam-0022.experiment.xml --noout --schema dra/xsd/1-5/SRA.experiment.xsd
xmllint afujiyam-0022.run.xml --noout --schema dra/xsd/1-5/SRA.run.xsd
```

* analysis は optional  






