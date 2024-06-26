configfile: "/mnt2/plastaumatic/config.yaml"

def get_read_f(wildcards):
    return config["samples"][wildcards.sample].split(",")[0]
def get_read_r(wildcards):
    return config["samples"][wildcards.sample].split(",")[1]

rule all:
    input:
        expand("{sample}/05-tbl/{sample}.fsa",sample=config['samples']),
        expand("{sample}/05-tbl/{sample}.tbl",sample=config['samples'])
rule trim:
    input:
        raw_f=get_read_f,
        raw_r=get_read_r
    output:
        trim_f="{sample}/01-trim/{sample}_1.fq",
        trim_r="{sample}/01-trim/{sample}_2.fq",
        html="{sample}/01-trim/{sample}.html",
        json="{sample}/01-trim/{sample}.json"
    threads:
        1
    log:
        "{sample}/00-logs/01-trim.log"
    shell:
        """
        fastp -i {input.raw_f} -I {input.raw_r} -o {output.trim_f} -O {output.trim_r} \
            -h {output.html} -j {output.json} -w {threads} --reads_to_process 10000000 &> {log}
        """
rule config:
    input:
        trim_f="{sample}/01-trim/{sample}_1.fq",
        trim_r="{sample}/01-trim/{sample}_2.fq",
        config=expand("{rp}/scripts/config_novo.txt",rp=config['repo'])
    output:
        "{sample}/{sample}_config.txt"
    params:
        prefix="{sample}",
        seed=config['seed'],
        range=config['range']
    shell:
        """
        readlen=$(head -4000 {params.prefix}/01-trim/{params.prefix}_1.fq|awk '{{if(NR%4==2) print length($1)}}' |sort |uniq -c|sort -k1 -nr|head -1|awk '{{print $2}}')
        cat {input.config} |sed "s|WORKDIR|{params.prefix}/02-assemble/|g"| sed "s|test|{params.prefix}|" |\
            sed "s|path_to_seed|{params.seed}|" |sed "s|range|{params.range}|"|sed "s|ReadLen|$readlen|"|\
            sed "s|read1|{input.trim_f}|" | sed "s|read2|{input.trim_r}|" > {output}
        """
rule assemble:
    input:
        "{sample}/{sample}_config.txt"
    output:
        directory("{sample}/02-assemble")
    params:
        novo_path=config['novo_path'],
        prefix="{sample}"
    log:
        "{sample}/00-logs/02-assemble.log"        
    shell:
        """
        mkdir -p {params.prefix}/02-assemble
        perl {params.novo_path} -c {input} &> {log}
        """
rule standardize:
    input:
        "{sample}/02-assemble"
    output:
        standardized="{sample}/03-standardize/{sample}.plastome.fa"
    params:
        prefix="{sample}",
        repo=config['repo'],
        gb=config['ref_gb']
    log:
        "{sample}/00-logs/03-standardize.log"
    shell:
        """
        {params.repo}/scripts/standardize_cpDNA.sh -d {input} -g {params.gb} -o {output.standardized} -p {params.prefix} &> {log}
        """
rule annotate:
    input:
        fa="{sample}/03-standardize/{sample}.plastome.fa",
        gb=config['ref_gb']        
    output:
        directory("{sample}/04-annotate")
    params:
        prefix="{sample}",
        repo=config['repo']
    log:
        "{sample}/00-logs/04-annotate.log"
    shell:
        """
        python3 {params.repo}/scripts/AnnoPlast.py -f {input.fa} -g {input.gb} -o {output} -p {params.prefix} &> {log}
        """
rule tbl:
    input:
        "{sample}/04-annotate"
    output:
        fsa="{sample}/05-tbl/{sample}.fsa",
        tbl="{sample}/05-tbl/{sample}.tbl"
    params:
        prefix="{sample}",
        repo=config['repo']
    shell:
        """
    	perl {params.repo}/scripts/gbf2tbl.pl {input}/{params.prefix}.gb
		mv {input}/{params.prefix}.fsa {output.fsa} 
        mv {input}/{params.prefix}.tbl {output.tbl}
        ln -s 03-standardize/{params.prefix}.plastome.fa {params.prefix}/{params.prefix}.plastome.fa
        ln -s 04-annotate/{params.prefix}.gb {params.prefix}/{params.prefix}.plastome.gb
        """
