# The CNNScoreVariants tool annotates a VCF with scores from a Neural Net as part of a single-sample workflow.
# The site-level scores are added to the INFO field of the VCF.
# The architecture arguments, info_key and tensor type arguments MUST be in agreement
# (e.g. 2D models must have tensor_type of read_tensor and info_key CNN_2D, 1D models have tensor_type reference and info_key CNN_1D)
# The INFO field key will be "1D_CNN" or "2D_CNN" depending on the neural net architecture used for inference.
# The architecture arguments specify pre-trained networks.
# New networks can be trained by the GATK tools: CNNVariantWriteTensors and CNNVariantTrain
# The bam file and index are only required by 2D CNNs which take a read-level tensor_type such as "read_tensor".
# For 1D CNNs the tensor_type is typically "reference".
# Parallelization over sites is controlled by the scatter_count variable.
workflow CNNScoreVariantsWorkflow {
    File input_vcf                  # The VCF to annotate with scores
    File input_vcf_index
    File reference_fasta
    File reference_dict
    File reference_fasta_index
    File resource_fofn              # File of VCF file names of resources of known SNPs and INDELs, (e.g. mills, gnomAD)
    File resource_fofn_index        # File of VCF file indices of resources
    File? bam_file                  # Bam (or bamout) file from which input_vcf was called, required by read-level architectures
    File? bam_file_index
    File? architecture_json         # Neural Net configuration for CNNScoreVariants
    File? architecture_hd5          # Pre-Trained weights and architecture for CNNScoreVariants
    String? tensor_type             # Keyword indicating the shape of the input tensor (e.g. read_tensor, reference)
    String info_key                 # The score key for the info field of the vcf (e.g. CNN_1D, CNN_2D)
    String tranches                 # Filtering threshold(s) in terms of sensitivity to overlapping known variants in resources
    String output_prefix            # Identifying string for this run which will be used to name output files (the gzipped VCF and BAMout)
    Int? inference_batch_size       # Batch size for python in CNNScoreVariants
    Int? transfer_batch_size        # Batch size for java transfers to python in CNNScoreVariants
    Int? intra_op_threads           # Tensorflow threading within nodes
    Int? inter_op_threads           # Tensorflow threading between nodes
    File? gatk_override
    String gatk_docker
    File calling_intervals
    Int scatter_count 
    Int? preemptible_attempts
    Int? cnn_task_mem_gb
    Int? cnn_task_cpu
    Int? mem_gb

    call SplitIntervals {
        input:
            gatk_override = gatk_override,
            scatter_count = scatter_count,
            intervals = calling_intervals,
            ref_fasta = reference_fasta,
            ref_dict = reference_dict,
            ref_fai = reference_fasta_index,
            preemptible_attempts = preemptible_attempts,
            gatk_docker = gatk_docker
    }

    scatter (calling_interval in SplitIntervals.interval_files) {

        call CNNScoreVariants {
            input:
                input_vcf = input_vcf,
                input_vcf_index = input_vcf_index,
                reference_fasta = reference_fasta,
                reference_dict = reference_dict,
                reference_fasta_index = reference_fasta_index,
                bam_file = bam_file,
                bam_file_index = bam_file_index,
                architecture_json = architecture_json,
                architecture_hd5 = architecture_hd5,
                tensor_type = tensor_type,
                inference_batch_size = inference_batch_size,
                transfer_batch_size = transfer_batch_size,
                intra_op_threads = intra_op_threads,
                inter_op_threads = inter_op_threads,
                output_prefix = output_prefix,
                interval_list = calling_interval,
                gatk_override = gatk_override,
                gatk_docker = gatk_docker,
                preemptible_attempts = preemptible_attempts,
                mem_gb = cnn_task_mem_gb,
                cpu = cnn_task_cpu
        }
    }

    call MergeVCFs as MergeVCF_CNN {
        input: 
            input_vcfs = CNNScoreVariants.cnn_annotated_vcf,
            output_vcf_name = output_prefix,
            preemptible_attempts = preemptible_attempts,
            gatk_override = gatk_override,
            gatk_docker = gatk_docker
    }

    call FilterVariantTranches {
        input:
            input_vcf = MergeVCF_CNN.merged_vcf,
            input_vcf_index = MergeVCF_CNN.merged_vcf_index,
            resource_fofn = resource_fofn,
            resource_fofn_index = resource_fofn_index,
            output_prefix = output_prefix,
            tranches = tranches,
            info_key = info_key,
            gatk_override = gatk_override,
            preemptible_attempts = preemptible_attempts,
            gatk_docker = gatk_docker
    }

    output {
        FilterVariantTranches.*
    }
}

task CNNScoreVariants {
    File input_vcf
    File input_vcf_index
    File reference_fasta
    File reference_dict
    File reference_fasta_index
    String output_prefix
    File? bam_file
    File? bam_file_index
    File? architecture_json
    File? architecture_hd5
    Int? inference_batch_size
    Int? transfer_batch_size
    Int? intra_op_threads
    Int? inter_op_threads
    String? tensor_type

    File interval_list
    File? gatk_override

    # Runtime parameters
    Int? mem_gb
    String gatk_docker
    Int? preemptible_attempts
    Int? disk_space_gb
    Int? cpu 

    # You may have to change the following two parameter values depending on the task requirements
    Int default_ram_mb = 6000
    Int default_disk_space_gb = 100

    # Mem is in units of GB but our command and memory runtime values are in MB
    Int machine_mem = if defined(mem_gb) then mem_gb *1000 else default_ram_mb
    Int command_mem = machine_mem / 2 # was machine_mem - 1000

command <<<
    
        set -e
        export GATK_LOCAL_JAR=${default="/root/gatk.jar" gatk_override}

        gatk --java-options "-Xmx${command_mem}m" \
        CNNScoreVariants \
        ${"-I " + bam_file} \
        -R ${reference_fasta} \
        -V ${input_vcf} \
        -O ${output_prefix}_cnn_annotated.vcf.gz \
        -L ${interval_list} \
        ${"--architecture " + architecture_json} \
        ${"--tensor-type " + tensor_type} \
        ${"--inference-batch-size " + inference_batch_size} \
        ${"--transfer-batch-size " + transfer_batch_size} \
        ${"--intra-op-threads " + intra_op_threads} \
        ${"--inter-op-threads " + inter_op_threads}

>>>

  runtime {
    docker: "${gatk_docker}"
    memory: machine_mem + " MB"
    disks: "local-disk " + select_first([disk_space_gb, default_disk_space_gb]) + " HDD"
    preemptible: select_first([preemptible_attempts, 3])
    cpu: select_first([cpu, 1])
    zones: "us-central1-b"
    bootDiskSizeGb: "16"
  }

  output {
    Array[File] log = glob("gatkStreamingProcessJournal*")
    File cnn_annotated_vcf = "${output_prefix}_cnn_annotated.vcf.gz"
    File cnn_annotated_vcf_index = "${output_prefix}_cnn_annotated.vcf.gz.tbi"
  }
}

task SplitIntervals {
    # inputs
    File? intervals
    File ref_fasta
    File ref_fai
    File ref_dict
    Int scatter_count
    String? split_intervals_extra_args

    File? gatk_override

    # runtime
    String gatk_docker
    Int? mem
    Int? preemptible_attempts
    Int? disk_space
    Int? cpu

    # Mem is in units of GB but our command and memory runtime values are in MB
    Int machine_mem = if defined(mem) then mem * 1000 else 3500
    Int command_mem = machine_mem - 500

    command {
        set -e
        export GATK_LOCAL_JAR=${default="/root/gatk.jar" gatk_override}

        gatk --java-options "-Xmx${command_mem}m" \
            SplitIntervals \
            -R ${ref_fasta} \
            ${"-L " + intervals} \
            -scatter ${scatter_count} \
            -O ./ \
            ${split_intervals_extra_args}
    }

    runtime {
        docker: "${gatk_docker}"
        memory: machine_mem + " MB"
        disks: "local-disk " + select_first([disk_space, 100]) + " HDD"
        preemptible: select_first([preemptible_attempts, 10])
        cpu: select_first([cpu, 1])
        bootDiskSizeGb: "16"
    }

    output {
        Array[File] interval_files = glob("*.intervals")
    }
}

task MergeVCFs {
    Array[File] input_vcfs
    String output_vcf_name   
    File? gatk_override

    # Runtime parameters
    Int? mem_gb
    String gatk_docker
    Int? preemptible_attempts
    Int? disk_space_gb
    Int? cpu 

    # You may have to change the following two parameter values depending on the task requirements
    Int default_ram_mb = 3000
    Int default_disk_space_gb = 100

    # Mem is in units of GB but our command and memory runtime values are in MB
    Int machine_mem = if defined(mem_gb) then mem_gb *1000 else default_ram_mb
    Int command_mem = machine_mem - 1000

command <<<   
        set -e
        export GATK_LOCAL_JAR=${default="/root/gatk.jar" gatk_override}

        gatk --java-options "-Xmx${command_mem}m" \
            MergeVcfs -I ${sep=' -I ' input_vcfs} \
            -O "${output_vcf_name}_cnn_scored.vcf.gz"
>>>
  runtime {
    docker: "${gatk_docker}"
    memory: machine_mem + " MB"
    disks: "local-disk " + select_first([disk_space_gb, default_disk_space_gb]) + " HDD"
    preemptible: select_first([preemptible_attempts, 3])
    cpu: select_first([cpu, 1])
    bootDiskSizeGb: "16"
  }
  output {
    File merged_vcf = "${output_vcf_name}_cnn_scored.vcf.gz"
    File merged_vcf_index = "${output_vcf_name}_cnn_scored.vcf.gz.tbi"
  }
}


task FilterVariantTranches {
    File input_vcf
    File input_vcf_index
    File resource_fofn
    File resource_fofn_index
    Array[File] resource_files = read_lines(resource_fofn)
    Array[File] resource_files_index = read_lines(resource_fofn_index)
    String output_prefix
    String tranches
    String info_key
    File? gatk_override

    # Runtime parameters
    Int? mem_gb
    String gatk_docker
    Int? preemptible_attempts
    Int? disk_space_gb
    Int? cpu

    String output_vcf = "${output_prefix}_cnn_filtered.vcf.gz"

    # You may have to change the following two parameter values depending on the task requirements
    Int default_ram_mb = 16000
    # WARNING: In the workflow, you should calculate the disk space as an input to this task (disk_space_gb).
    Int default_disk_space_gb = 200

    # Mem is in units of GB but our command and memory runtime values are in MB
    Int machine_mem = if defined(mem_gb) then mem_gb *1000 else default_ram_mb
    Int command_mem = machine_mem - 1000

command <<<
        set -e
        export GATK_LOCAL_JAR=${default="/root/gatk.jar" gatk_override}

        gatk --java-options "-Xmx${command_mem}m" \
        FilterVariantTranches \
        -V ${input_vcf} \
        --output ${output_vcf} \
        -resource ${sep=" -resource " resource_files} \
        -info-key ${info_key} \
        ${tranches}
>>>

  runtime {
    docker: "${gatk_docker}"
    memory: machine_mem + " MB"
    # Note that the space before HDD and HDD should be included.
    disks: "local-disk " + select_first([disk_space_gb, default_disk_space_gb]) + " HDD"
    preemptible: select_first([preemptible_attempts, 3])
    cpu: select_first([cpu, 1])
    bootDiskSizeGb: "16"
  }

  output {
    File cnn_filtered_vcf = "${output_vcf}"
    File cnn_filtered_vcf_index = "${output_vcf}.tbi"
  }
}

