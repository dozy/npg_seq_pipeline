use strict;
use warnings;
use Test::More tests => 3;
use Test::Exception;
use Cwd;
use Perl6::Slurp;
use JSON;

use npg_tracking::util::abs_path qw(abs_path);
use t::util;

my $util = t::util->new();
my $dir = $util->temp_directory();

use_ok('npg_pipeline::function::p4_stage1_analysis');
my $current = abs_path(getcwd());

# Copy cache dir to a temp location since a tag file will
# be created there.
my $new = "$dir/1234_samplesheet.csv";
`cp -r t/data/p4_stage1_analysis/* $dir`;
local $ENV{NPG_CACHED_SAMPLESHEET_FILE} = $new;
local $ENV{NPG_WEBSERVICE_CACHE_DIR} = $dir;

#################################
# mock references
#################################
my $repos_root = $dir . q{/srpipe_references};
`mkdir -p $repos_root/references/PhiX/default/all/bwa0_6`;
`mkdir -p $repos_root/references/PhiX/default/all/fasta`;
`touch $repos_root/references/PhiX/default/all/bwa0_6/phix_unsnipped_short_no_N.fa`;
`touch $repos_root/references/PhiX/default/all/fasta/phix_unsnipped_short_no_N.fa`;

$util->create_analysis();
my $runfolder = $util->analysis_runfolder_path() . '/';
`cp t/data/runfolder/Data/RunInfo.xml $runfolder`;

my $bc_path = q{/nfs/sf45/IL2/analysis/123456_IL2_1234/Data/Intensities/BaseCalls};

my $bam_generator = npg_pipeline::function::p4_stage1_analysis->new(
    run_folder                    => q{123456_IL2_1234},
    repository                    => $repos_root,
    runfolder_path                => $util->analysis_runfolder_path(),
    timestamp                     => q{20090709-123456},
    verbose                       => 0,
    id_run                        => 1234,
    _extra_tradis_transposon_read => 1,
    bam_basecall_path             => $util->analysis_runfolder_path() . q{/Data/Intensities/BaseCalls},
  );

subtest 'basics' => sub {
  plan tests => 5;

  isa_ok($bam_generator, q{npg_pipeline::function::p4_stage1_analysis}, q{$bam_generator});
  is($bam_generator->_extra_tradis_transposon_read, 1, 'TraDIS set');
  $bam_generator->_extra_tradis_transposon_read(0);
  is($bam_generator->_extra_tradis_transposon_read, 0, 'TraDIS not set');
  isa_ok($bam_generator->lims, 'st::api::lims', 'cached lims object');
  
  my $alims = $bam_generator->lims->children_ia;
  my $position = 8;
  is($bam_generator->_get_number_of_plexes_excluding_control($alims->{$position}),
    2, 'correct number of plexes');
};

subtest 'check_save_arguments' => sub {
  plan tests => 31;
 
  my $bbp = $bam_generator->bam_basecall_path;
  my $unique = $bam_generator->_job_id();
 
  my $da = $bam_generator->generate();
  ok ($da && @{$da}==8, 'eight definitions returned');
  my $d = $da->[0];
  isa_ok ($d, 'npg_pipeline::function::definition');
  is ($d->created_by, 'npg_pipeline::function::p4_stage1_analysis', 'created by');
  is ($d->created_on, q{20090709-123456}, 'created on');
  is ($d->identifier, 1234, 'identifier');
  ok (!$d->excluded, 'step is not excluded');
  ok (!$d->immediate_mode, 'not immediate mode');
  is ($d->queue, 'default', 'default queue');
  is ($d->job_name, 'p4_stage1_analysis_1234_20090709-123456', 'job name');
  is ($d->fs_slots_num, 4, '4 sf slots');
  is ($d->num_hosts, 1, 'one host');
  is_deeply ($d->num_cpus, [3], 'num cpus as an array');
  is ($d->log_file_dir, "$bbp/log", 'log dir');
  is ($d->memory, 7000, 'memory');
  is ($d->command_preexec,
      "npg_pipeline_preexec_references --repository $repos_root",
      'preexec command');
  ok ($d->has_composition, 'composition object is set');
  my $composition = $d->composition;
  isa_ok ($composition, 'npg_tracking::glossary::composition');
  is ($composition->num_components, 1, 'one component');
  my $component = $composition->get_component(0);
  is ($component->id_run, 1234, 'run id correct');
  is ($component->position, 1, 'position correct');
  ok (!defined $component->tag_index, 'tag index undefined');

  my $intensities_dir = $dir . '/nfs/sf45/IL2/analysis/123456_IL2_1234/Data/Intensities';
  my $expected = {
          '1' => 'bash -c \' cd ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane1/log && vtfp.pl -splice_nodes \'"\'"\'bamadapterfind:-bamcollate:\'"\'"\' -prune_nodes \'"\'"\'fs1p_tee_split:__SPLIT_BAM_OUT__-\'"\'"\' -o run_1234_1.json -param_vals ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane1/param_files/1234_1_p4s1_pv_in.json -export_param_vals 1234_1_p4s1_pv_out_' . $unique . '.json -keys cfgdatadir -vals $(dirname $(readlink -f $(which vtfp.pl)))/../data/vtlib/ -keys aligner_numthreads -vals 1 -keys s2b_mt_val -vals 1 -keys bamsormadup_numthreads -vals 1 -keys br_numthreads_val -vals 3  $(dirname $(dirname $(readlink -f $(which vtfp.pl))))/data/vtlib/bcl2bam_phix_deplex_wtsi_stage1_template.json && viv.pl -s -x -v 3 -o viv_1234_1.log run_1234_1.json && qc --check spatial_filter --id_run 1234 --position 1 --qc_out ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc < ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_1.bam.filter.stats \'',
          '2' => 'bash -c \' cd ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane2/log && vtfp.pl -splice_nodes \'"\'"\'bamadapterfind:-bamcollate:\'"\'"\' -prune_nodes \'"\'"\'fs1p_tee_split:__SPLIT_BAM_OUT__-\'"\'"\' -o run_1234_2.json -param_vals ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane2/param_files/1234_2_p4s1_pv_in.json -export_param_vals 1234_2_p4s1_pv_out_' . $unique . '.json -keys cfgdatadir -vals $(dirname $(readlink -f $(which vtfp.pl)))/../data/vtlib/ -keys aligner_numthreads -vals 1 -keys s2b_mt_val -vals 1 -keys bamsormadup_numthreads -vals 1 -keys br_numthreads_val -vals 3  $(dirname $(dirname $(readlink -f $(which vtfp.pl))))/data/vtlib/bcl2bam_phix_deplex_wtsi_stage1_template.json && viv.pl -s -x -v 3 -o viv_1234_2.log run_1234_2.json && qc --check spatial_filter --id_run 1234 --position 2 --qc_out ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc < ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_2.bam.filter.stats \'',
          '3' => 'bash -c \' cd ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane3/log && vtfp.pl -splice_nodes \'"\'"\'bamadapterfind:-bamcollate:\'"\'"\' -prune_nodes \'"\'"\'fs1p_tee_split:__SPLIT_BAM_OUT__-\'"\'"\' -o run_1234_3.json -param_vals ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane3/param_files/1234_3_p4s1_pv_in.json -export_param_vals 1234_3_p4s1_pv_out_' . $unique . '.json -keys cfgdatadir -vals $(dirname $(readlink -f $(which vtfp.pl)))/../data/vtlib/ -keys aligner_numthreads -vals 1 -keys s2b_mt_val -vals 1 -keys bamsormadup_numthreads -vals 1 -keys br_numthreads_val -vals 3  $(dirname $(dirname $(readlink -f $(which vtfp.pl))))/data/vtlib/bcl2bam_phix_deplex_wtsi_stage1_template.json && viv.pl -s -x -v 3 -o viv_1234_3.log run_1234_3.json && qc --check spatial_filter --id_run 1234 --position 3 --qc_out ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc < ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_3.bam.filter.stats \'',
          '4' => 'bash -c \' cd ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane4/log && vtfp.pl -splice_nodes \'"\'"\'bamadapterfind:-bamcollate:\'"\'"\' -prune_nodes \'"\'"\'fs1p_tee_split:__SPLIT_BAM_OUT__-\'"\'"\' -o run_1234_4.json -param_vals ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane4/param_files/1234_4_p4s1_pv_in.json -export_param_vals 1234_4_p4s1_pv_out_' . $unique . '.json -keys cfgdatadir -vals $(dirname $(readlink -f $(which vtfp.pl)))/../data/vtlib/ -keys aligner_numthreads -vals 1 -keys s2b_mt_val -vals 1 -keys bamsormadup_numthreads -vals 1 -keys br_numthreads_val -vals 3  $(dirname $(dirname $(readlink -f $(which vtfp.pl))))/data/vtlib/bcl2bam_phix_deplex_wtsi_stage1_template.json && viv.pl -s -x -v 3 -o viv_1234_4.log run_1234_4.json && qc --check spatial_filter --id_run 1234 --position 4 --qc_out ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc < ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_4.bam.filter.stats \'',
          '5' => 'bash -c \' cd ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane5/log && vtfp.pl -splice_nodes \'"\'"\'bamadapterfind:-bamcollate:\'"\'"\' -prune_nodes \'"\'"\'fs1p_tee_split:__SPLIT_BAM_OUT__-\'"\'"\' -o run_1234_5.json -param_vals ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane5/param_files/1234_5_p4s1_pv_in.json -export_param_vals 1234_5_p4s1_pv_out_' . $unique . '.json -keys cfgdatadir -vals $(dirname $(readlink -f $(which vtfp.pl)))/../data/vtlib/ -keys aligner_numthreads -vals 1 -keys s2b_mt_val -vals 1 -keys bamsormadup_numthreads -vals 1 -keys br_numthreads_val -vals 3  $(dirname $(dirname $(readlink -f $(which vtfp.pl))))/data/vtlib/bcl2bam_phix_deplex_wtsi_stage1_template.json && viv.pl -s -x -v 3 -o viv_1234_5.log run_1234_5.json && qc --check spatial_filter --id_run 1234 --position 5 --qc_out ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc < ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_5.bam.filter.stats \'',
          '6' => 'bash -c \' cd ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane6/log && vtfp.pl -splice_nodes \'"\'"\'bamadapterfind:-bamcollate:\'"\'"\' -prune_nodes \'"\'"\'fs1p_tee_split:__SPLIT_BAM_OUT__-\'"\'"\' -o run_1234_6.json -param_vals ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane6/param_files/1234_6_p4s1_pv_in.json -export_param_vals 1234_6_p4s1_pv_out_' . $unique . '.json -keys cfgdatadir -vals $(dirname $(readlink -f $(which vtfp.pl)))/../data/vtlib/ -keys aligner_numthreads -vals 1 -keys s2b_mt_val -vals 1 -keys bamsormadup_numthreads -vals 1 -keys br_numthreads_val -vals 3  $(dirname $(dirname $(readlink -f $(which vtfp.pl))))/data/vtlib/bcl2bam_phix_deplex_wtsi_stage1_template.json && viv.pl -s -x -v 3 -o viv_1234_6.log run_1234_6.json && qc --check spatial_filter --id_run 1234 --position 6 --qc_out ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc < ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_6.bam.filter.stats \'',
          '7' => 'bash -c \' cd ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane7/log && vtfp.pl -splice_nodes \'"\'"\'bamadapterfind:-bamcollate:\'"\'"\' -prune_nodes \'"\'"\'fs1p_tee_split:__SPLIT_BAM_OUT__-\'"\'"\' -o run_1234_7.json -param_vals ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane7/param_files/1234_7_p4s1_pv_in.json -export_param_vals 1234_7_p4s1_pv_out_' . $unique . '.json -keys cfgdatadir -vals $(dirname $(readlink -f $(which vtfp.pl)))/../data/vtlib/ -keys aligner_numthreads -vals 1 -keys s2b_mt_val -vals 1 -keys bamsormadup_numthreads -vals 1 -keys br_numthreads_val -vals 3  $(dirname $(dirname $(readlink -f $(which vtfp.pl))))/data/vtlib/bcl2bam_phix_deplex_wtsi_stage1_template.json && viv.pl -s -x -v 3 -o viv_1234_7.log run_1234_7.json && qc --check spatial_filter --id_run 1234 --position 7 --qc_out ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc < ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_7.bam.filter.stats \'',
          '8' => 'bash -c \' cd ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane8/log && vtfp.pl   -o run_1234_8.json -param_vals ' . $intensities_dir . '/BaseCalls/p4_stage1_analysis/lane8/param_files/1234_8_p4s1_pv_in.json -export_param_vals 1234_8_p4s1_pv_out_' . $unique . '.json -keys cfgdatadir -vals $(dirname $(readlink -f $(which vtfp.pl)))/../data/vtlib/ -keys aligner_numthreads -vals 1 -keys s2b_mt_val -vals 1 -keys bamsormadup_numthreads -vals 1 -keys br_numthreads_val -vals 3  $(dirname $(dirname $(readlink -f $(which vtfp.pl))))/data/vtlib/bcl2bam_phix_deplex_wtsi_stage1_template.json && viv.pl -s -x -v 3 -o viv_1234_8.log run_1234_8.json && qc --check spatial_filter --id_run 1234 --position 8 --qc_out ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc < ' . $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_8.bam.filter.stats \'',
  };

  foreach my $d (@{$da}) {
    my $p = $d->composition()->get_component(0)->position();
    is ($d->command, $expected->{$p}, "command correct for lane $p");
  }

  my $pfname = $dir . $bc_path. q[/p4_stage1_analysis/lane1/param_files/1234_1_p4s1_pv_in.json];
  ok (-e $pfname, 'params file exists');
  my $h = from_json(slurp($pfname));

  $expected = {
     'assign' => [
        {
	  'i2b_thread_count' => 3,
	  'bid_implementation' => 'bambi',
	  'seqchksum_file' => $intensities_dir . '/BaseCalls/1234_1.post_i2b.seqchksum',
	  'scramble_reference_fasta' => $dir . '/srpipe_references/references/PhiX/default/all/fasta/phix_unsnipped_short_no_N.fa',
	  'i2b_rg' => '1234_1',
	  'spatial_filter_stats' => $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_1.bam.filter.stats',
	  'i2b_pu' => '123456_IL2_1234_1',
	  'tileviz_dir' => $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc/tileviz/1234_1',
	  'reference_phix' => $dir . '/srpipe_references/references/PhiX/default/all/bwa0_6/phix_unsnipped_short_no_N.fa',
	  'unfiltered_cram_file' => $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_1.unfiltered.cram',
	  'qc_check_qc_out_dir' => $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/archive/qc',
	  'i2b_lane' => '1',
	  'bwa_executable' => 'bwa0_6',
	  'filtered_bam' => $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_1.bam',
	  'samtools_executable' => 'samtools1',
	  'i2b_library_name' => '51021',
	  'outdatadir' => $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal',
	  'i2b_run_path' => $dir . q[/nfs/sf45/IL2/analysis/123456_IL2_1234],
	  'teepot_tempdir' => '.',
	  'split_prefix' => $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/lane1',
	  'illumina2bam_jar' => 'Illumina2bam.jar',
	  'i2b_intensity_dir' => $intensities_dir,
	  'i2b_sample_aliases' => 'SRS000147',
	  'phix_alignment_method' => 'bwa_aln_se',
	  'spatial_filter_file' => $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_1.bam.filter',
	  'md5filename' => $intensities_dir . '/Bustard1.3.4_09-07-2009_auto/PB_cal/1234_1.bam.md5',
	  'teepot_mval' => '2G',
	  'i2b_runfolder' => '123456_IL2_1234',
	  'i2b_study_name' => '"SRP000031: 1000Genomes Project Pilot 1"',
	  'i2b_basecalls_dir' => $intensities_dir . '/BaseCalls',
	  'teepot_wval' => '500',
	  'qc_check_qc_in_dir' => $intensities_dir . '/BaseCalls',
	  'qc_check_id_run' => '1234',
        },
    ],
  };

  is_deeply($h, $expected, 'correct json file content (for p4 stage1 params file)');

 };

1;

