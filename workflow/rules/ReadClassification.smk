################ Unmapped Read Classification #####################
    # Kraken2: (Wood, Lu and Langmead, 2019)
    # KrakenTools: (Lu, 2021)
    # Metaphaln3: (Beghini et al., 2021)
    # Bracken: (Lu et al., 2017)
##################################################################

def classification_input_r1(wildcards): 
    if config["ProcessBam"]["FromFastq"]:
        return("../results/unmapped_fastq_ffq/{sample}_unmapped_1.fastq")
            
    else: 
        return("../results/unmapped_fastq/{sample}_unmapped_1.fastq")

def classification_input_r2(wildcards): 
    if config["ProcessBam"]["FromFastq"]:
        return("../results/unmapped_fastq_ffq/{sample}_unmapped_2.fastq")
            
    else: 
        return("../results/unmapped_fastq/{sample}_unmapped_2.fastq")
                
def classification_sum_input(wildcards): 
    input_list = []
    if config["ProcessBam"]["FromFastq"]: 
        input_list.extend(
            expand(
                [
                    "../results/alignment_stats_ffq/concatenated_alignment_statistics.txt",

                ]
            )
        )
    else: 
        input_list.extend(
            expand(
                [
                    "../results/alignment_stats/concatenated_alignment_statistics.txt",
                ],

            )
        )
    
    return(input_list)


rule kraken_classification: 
    """
        Read classification of unmapped reads with kraken2
    """
    output: 
        txt = "../results/kraken_out/mpa_report/{sample}_report.txt",
        report = "../results/kraken_out/report/{sample}_kraken_report",

    input: 
        r1 = classification_input_r1,
        r2 = classification_input_r2,
    threads: config["KrakenClassification"]["Threads"]
    conda: 
        "../envs/classification_env.yaml",
    params:
        kraken_db = config["kraken_db_location"],
        conf_score = config["KrakenClassification"]["ConfidenceScore"]
    shell: 
        r"""
            kraken2 -db {params.kraken_db} \
            --output {output.report} \
            --report {output.txt} \
            --confidence {params.conf_score} \
            --paired {input.r1} {input.r2}
         """


rule extract_taxon: 
    """
        Extract taxon (or group) of choosing and convert to fastq 
    """
    output: 
        read1 = "../results/kraken_taxon_extract/{sample}_extract_1.fastq",
        read2 = "../results/kraken_taxon_extract/{sample}_extract_2.fastq",
    input: 
        krak_file = "../results/kraken_out/report/{sample}_kraken_report",
        krak_reprt = "../results/kraken_out/mpa_report/{sample}_report.txt",
        r1 = classification_input_r1,
        r2 = classification_input_r2,

    conda: 
        "../envs/classification_env.yaml",
    params: 
        taxa = config["ExtractKrakenTaxa"]["taxon_choice"],
    threads: 
        8
    shell: 
        """
        extract_kraken_reads.py -k {input.krak_file} \
        -s1 {input.r1} -s2 {input.r2} \
        --output {output.read1} \
        --output2 {output.read2} \
        --fastq-output \
        --taxid {params.taxa} \
        --include-children \
        --report {input.krak_reprt} 
        """


rule convert_to_mpa: 
    """
        Convert kraken output to mpa style report
    """
    output: 
        mpa_txt = "../results/kraken_out/mpa_out/{sample}_mpa_conv_report.txt",
    input: 
        krak_file = "../results/kraken_out/mpa_report/{sample}_report.txt",
    conda: 
        "../envs/classification_env.yaml",
    shell: 
        "kreport2mpa.py -r {input.krak_file} -o {output.mpa_txt} --display-header"


rule combine_mpa_reports: 
    """
        Combine MPA reports into one file with samples + taxonomic classification
    """
    output: 
        combined_report = "../results/kraken_out/combined_report/kraken_bacterial_report.txt"
    input: 
        mpa_files = expand("../results/kraken_out/mpa_out/{sample}_mpa_conv_report.txt", sample = samples),
    conda: 
        "../envs/classification_env.yaml",
    shell: 
        "combine_mpa.py -i {input.mpa_files} -o {output.combined_report}"


rule generate_clean_kraken_summaries: 
    """
        Generate plots and clean taxonomic summary tables 
    """
    output: 
        kingdom_table = "../results/kraken_results/tables/kingdom_table_tidy.txt",
        genus_table = "../results/kraken_results/tables/genus_table_tidy.txt",
        spp_table = "../results/kraken_results/tables/species_table_tidy.txt",
        classified_reads = "../results/kraken_results/tables/classified_reads_table.txt",
        classified_reads_plot = "../results/kraken_results/plots/classified_reads_plot.pdf"
    input:
        combined_report = "../results/kraken_out/combined_report/kraken_bacterial_report.txt"
    params:
        kraken_db_type = config["KrakenSummaries"]["KrakenDbStandard"]
    script: 
        "../scripts/generate_kraken_summaries.R"


rule generate_classification_summary: 
    """
        Get classification number from alignment and classification statistics
    """
    output: 
        human_read_tbl = "../results/kraken_results/classification_stat/classified_reads_wide.txt",
        long_read_tbl = "../results/kraken_results/classification_stat/classified_reads_long.txt",
    input: 
        classified_reads = "../results/kraken_results/tables/classified_reads_table.txt",
        alignment_stats = classification_sum_input
    script: 
        "../scripts/combined_kraken_alignment_stat_ffq.R"


rule plot_classifiedVsUnclassified_reads: 
    """
        Plot classified vs unclassified reads 
    """
    output: 
        classified_proportions = "../results/kraken_results/plots/classified_proportions.pdf", 
    input: 
        long_read_tbl = "../results/kraken_results/classification_stat/classified_reads_long.txt",
    script: 
        "../scripts/plot_classifiedVsunclassified_reads.R"


rule plot_stratified_classifications: 
    """
        Plot heatmaps of genus and species level classifications
    """
    output: 
        genus_heatmap = "../results/kraken_results/plots/genus_heatmap.pdf", 
        species_heatmap = "../results/kraken_results/plots/species_heatmap.pdf", 
        stratified_heatmap = "../results/kraken_results/plots/stratified_heatmap.pdf",
    input: 
        genus_table = "../results/kraken_results/tables/genus_table_tidy.txt",
        spp_table = "../results/kraken_results/tables/species_table_tidy.txt",
    params: 
        strat_thresh = config["KrakenSummaries"]["StratThreshold"],
        genus_thresh = config["KrakenSummaries"]["GenusReadThreshold"],
        species_thresh = config["KrakenSummaries"]["SpeciesReadThreshold"]
    script: 
        "../scripts/plot_facet_species.R"


rule generate_metaphlan_report: 
    """
        Classify unmapped reads using MetaPhlAn3
    """
    output:
        txt_out = "../results/metaphlan_out/taxa_profile/{sample}_taxa_prof.txt",
        bowtie_out = "../results/metaphlan_out/bowtie2_aln/{sample}.bowtie2.bz2",
    input: 
        read_1 = classification_input_r1,
        read_2 = classification_input_r2,
    params: 
        db_loc = config["MetaphlanClassification"]["Database"],
        proc = config["MetaphlanClassification"]["NProc"]
    conda: 
        "../envs/classification_env.yaml",
    shell: 
        r"""
            metaphlan {input.read_1},{input.read_2} \
            --bowtie2out {output.bowtie_out} \
            --input_type fastq \
            -o {output.txt_out} \
            --unknown_estimation \
            --add_viruses \
            --nproc {params.proc}
            
         """


rule concatenate_clean_samples: 
    """
        Concatenate metaphlan classification tables
    """
    output: 
        concat_tbl = "../results/metaphlan_out/taxa_profile_clean/merged_tbl/merged_taxa_prof_clean.txt",
    input: 
        cln_out = expand("../results/metaphlan_out/taxa_profile/{sample}_taxa_prof.txt", sample = samples),
    conda: 
        "../envs/classification_env.yaml",
    shell: 
        "merge_metaphlan_tables.py {input.cln_out} > {output.concat_tbl}" 


rule clean_metaphlan_report: 
    """
        Generate clean metaphlan classification tables
    """
    output: 
        tbl_out = "../results/metaphlan_out/taxa_profile_clean/{sample}_taxa_prof_clean.txt", 
    input: 
        txt_out = "../results/metaphlan_out/taxa_profile/{sample}_taxa_prof.txt",
    shell: 
        "grep 's__\|UNKNOWN' {input.txt_out} | cut -f1,3 > {output.tbl_out}"


rule generate_clean_metaphlan_summaries: 
    """
        Generate classification summaries of kingdom, genus and species 
    """
    output: 
        kingdom_table = "../results/metaphlan_out/clean_summaries/kingdom_table_tidy.txt",
        genus_table = "../results/metaphlan_out/clean_summaries/genus_table_tidy.txt",
        spp_table = "../results/metaphlan_out/clean_summaries/species_table_tidy.txt", 
    input:
        concat_tbl = "../results/metaphlan_out/taxa_profile_clean/merged_tbl/merged_taxa_prof_clean.txt",
    script:
        "../scripts/generate_metaphlan_summaries.R" 


rule bracken_reestimation: 
    """
        Reestimate kraken classified reads using bracken
    """
    output: 
        brack_out = "../results/bracken_reestimation/bracken_out/{sample}_bracken.txt", 
    input: 
        txt = "../results/kraken_out/mpa_report/{sample}_report.txt",
    params: 
        bracken_db = config["BrackenReestimation"]["BrakenDb"],
        class_lvl = config["BrackenReestimation"]["ClassificationLvl"],
        dist_thresh = config["BrackenReestimation"]["DistributionThresh"],
    shell: 
        r"""
            bracken -d {params.bracken_db} \
            -i {input.txt} -o {output.brack_out} \
            -l {params.class_lvl} \
            -t {params.dist_thresh}
         """


rule concatenate_bracken_results: 
    """
        Concatenate Bracken Output
    """
    output: 
        txt = "../results/bracken_reestimation/concat_bracken_out/concatenated_bracken_report.txt",
    input: 
        brack_out = expand("../results/bracken_reestimation/bracken_out/{sample}_bracken.txt", sample = samples), 
    params: 
        filename = "FILENAME", 
    shell: 
        r"""
            awk '{{print $0 "\t" {params.filename}}}' {input.brack_out} > {output.txt}

         """


rule plot_bracken_results: 
    """
        Plot Bracken output
    """
    output: 
        bracken_stratified_heatmap  = "../results/bracken_reestimation/plots/stratified_species_heatmaps.pdf",
        bracken_overall_heatmap = "../results/bracken_reestimation/plots/overall_species_heatmap.pdf",
        added_reads_plot = "../results/bracken_reestimation/plots/added_reads_plot.pdf"
    input: 
        conc_input = "../results/bracken_reestimation/concat_bracken_out/concatenated_bracken_report.txt",
    params: 
        bracken_threshold = config["BrackenReestimation"]["PlotThreshold"],
    script: 
        "../scripts/plot_bracken_results.R"