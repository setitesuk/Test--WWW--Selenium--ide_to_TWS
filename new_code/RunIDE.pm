# based on  Test::WWW::Selenium::Conversion::IDE by Andy Brown (setitesuk@gmail.com)
# based on commands as translated by Selenium Perl Formatter by Nathan Broderick https://addons.mozilla.org/en-US/firefox/user/5989997/
package Test::WWW::Selenium::RunIDE;

use strict;
use warnings;
use Carp;
use English q{-no_match_vars};
use Test::More; # this is designed to be a helper for tests, OK
use Test::WWW::Selenium; # we are going to run the tests in this
use XML::LibXML;
use base q{Exporter};
use Readonly; Readonly::Scalar our $VERSION => 0.4;

our @EXPORT = qw{ ide_to_TWS_run_from_suite_file ide_to_TWS_run_from_test_file };

Readonly::Scalar our $DEFAULT_SELENIUM_LOCATION => q{t/selenium_tests};

sub ide_to_TWS_run_from_suite_file {
  my ( $sel, $suite_file, $sel_test_root ) = @_;
  $sel_test_root ||= $DEFAULT_SELENIUM_LOCATION;

  my $parser = XML::LibXML->new();
  my $suite = $parser->parse_html_file( qq{$sel_test_root/$suite_file} );
  my @tests = $suite->getElementsByTagName( q{a} );
  foreach my $test ( @tests ) {
    my $test_file = $test->getAttribute( q{href} );
    $test_file =~ s{[.]/}{}xms;
    ide_to_TWS_run_from_test_file( $sel, {
      test_file => $test_file,
      sel_test_root => $sel_test_root,
      parser => $parser,
    } );
  }
  return 1;
}

sub ide_to_TWS_run_from_test_file {
  my ( $sel, $args ) = @_;
  my $test_file = $args->{test_file};
  my $sel_test_root = $args->{sel_test_root} || $DEFAULT_SELENIUM_LOCATION;
  my $parser = $args->{parser} || XML::LibXML->new();

  my $test_dom = $parser->parse_html_file( qq{$sel_test_root/$test_file} );
  my @title_tags = $test_dom->getElementsByTagName( q{title} );
  my $title = $title_tags[0]->firstChild->nodeValue();
  note qq{Running Selenium Test: '$title'};

  my ($tbody) = $test_dom->getElementsByTagName( q{tbody} );
  foreach my $action_set ( $tbody->childNodes() ) {
    my $nodeName = $action_set->nodeName ;
    if ($nodeName !~ 'tr') {
        if ($nodeName =~ '#comment') {
            note $action_set->toString();
        }
        next;
    }
    my ( $action, $operand_1, $operand_2 ) = $action_set->getElementsByTagName( q{td} );
    foreach my $node ( $action, $operand_1, $operand_2 ) {
      if ( defined $node && defined $node->firstChild ) {
        $node = $node->firstChild->nodeValue();
      } else {
        $node = q{};
      }
    }
    if ( $operand_1 =~ m{\A[(]?//}xms ) {
      $operand_1 = q{xpath=} . $operand_1;
    }
    my $test_args = {
      action => $action,
      operand_1 => $operand_1,
      operand_2 => $operand_2,
    };
    _ide_to_TWS_convert_to_method_and_test( $sel, $test_args);
  }
  return 1;
}

sub expand_args {
    my ( $sel, $args ) = @_;
    my @return = ();
    if (defined $args->{operand_1}) {
        $return[0] =  $args->{operand_1};
    }
    
    if (defined $args->{operand_2}) {
        my $value = $args->{operand_2};
        $value =~ s/\$\{([^}]+)}/$sel->{store}->{$1}/g;
        $return[1] =  $value ;
    }
    return @return; 
}

sub is_title {
    my ($sel, $args) = @_;
    my ($a1) = &expand_args($sel, $args );
    $a1 =~ s/^exact://;
    $sel->title_is($a1);
}

sub wait_for_text {
    my ($sel, $args) = @_;
    WAIT: {
        for (1..60) {
            if (eval { $sel->is_text_present(&expand_args) }) {
                pass;
                last WAIT;
            }
            sleep(1);
        }
        fail("timeout");
    }
}

sub click_and_wait {
    my ($sel, $args) = @_;
    $sel->click_ok(&expand_args);
    $sel->wait_for_page_to_load_ok("30000");
    
}

sub store_eval {
    my ($sel, $args) = @_;
    $sel->{store}->{$args->{operand_2}} = $sel->get_eval($args->{operand_1});
}
    
sub _ide_to_TWS_convert_to_method_and_test {
  my ( $sel, $args ) = @_;
  # action callbacks are based on the translation the Selenium Perl exporter does
  # **this is an incomplete list**
  my %actions = (
    open                    => sub {  $sel->open_ok(&expand_args); },
    verifyTitle             => \&is_title ,
    assertTitle             => \&is_title,
    verifyText              => sub { $sel->is_text_present_ok(&expand_args); },
    verifyTextPresent       => sub { $sel->is_text_present_ok(&expand_args); },
    assertText              => sub { $sel->is_text_present_ok(&expand_args); },
    assertTextPresent       => sub { $sel->is_text_present_ok(&expand_args); },
    waitForElementPresent   => \&wait_for_text,
    waitForText             => \&wait_for_text,
    clickAndWait            => \&click_and_wait,
    click                   => sub { $sel->click_ok(&expand_args); },
    type                    => sub { $sel->type_ok(&expand_args); },
    select                  => sub { $sel->select_ok(&expand_args); },
    storeEval               => \&store_eval,
    stop                    => sub { $sel->stop() },
  );
  eval {
   $actions{$args->{action}}( $sel, $args );
   1;
  } or do {
    diag explain $args;
    diag qq{\t$EVAL_ERROR};
  };
  return;
}

1;

