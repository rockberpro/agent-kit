#!/usr/bin/env bash
# Brings a project's .agents/hooks/ and .agents/settings.json in line with this plugin.
#
#   sync-hooks.sh            report only (default)
#   sync-hooks.sh --apply    create what is missing; never replace what exists
#   sync-hooks.sh --apply --force   also replace guard copies that differ from the plugin
#
# Run from the project root. The scaffold uses --apply; update-hooks reports first, shows
# the diffs, and only then --force. Every line of output is one finding:
#   ok|missing|outdated|added|updated|legacy|linked <what>
# A symlink (hook or settings.json) belongs to whatever it points at — another package,
# another repo — so it is reported as `linked` and never written through.
# Exit: 0 nothing left to do, 1 findings left (report mode, or outdated without --force),
# 2 usage/environment error.
set -uo pipefail

apply=0; force=0
for a in "$@"; do
  case "$a" in
    --apply) apply=1 ;;
    --force) force=1 ;;
    *) echo "usage: $0 [--apply [--force]]" >&2; exit 2 ;;
  esac
done
perl -MJSON::PP -e1 2>/dev/null || { echo "perl with JSON::PP is required (it ships with git)" >&2; exit 2; }

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARDS="master-guard secret-guard memory-drift-guard"
URL="https://gitlab.univates.br/gitlab/pacotes/agent-kit.git"
S=.agents/settings.json
left=0
say() { printf '%-8s %s\n' "$1" "$2"; case "$1" in missing|outdated|legacy|linked) left=1 ;; esac; }

[ -d .agents ] || { echo "no .agents/ here — run from the project root, after the scaffold" >&2; exit 2; }
mkdir -p .agents/hooks

# --- guard copies ---------------------------------------------------------------------
for g in $GUARDS; do
  dst=".agents/hooks/$g.sh" src="$KIT/hooks/$g.sh"
  if [ -L "$dst" ]; then
    say linked "$dst -> $(readlink "$dst") (managed there; left alone)"
  elif [ ! -e "$dst" ]; then
    if [ $apply = 1 ]; then cp "$src" "$dst" && chmod +x "$dst" && say added "$dst"; else say missing "$dst"; fi
  elif ! cmp -s "$src" "$dst"; then
    if [ $apply = 1 ] && [ $force = 1 ]; then cp "$src" "$dst" && chmod +x "$dst" && say updated "$dst"; else say outdated "$dst"; fi
  else
    say ok "$dst"
  fi
done

# --- settings.json --------------------------------------------------------------------
# perl + JSON::PP, not jq: it ships with git on Windows (Git Bash) and Linux alike.
# ponytail: JSON::PP keeps no key order, so a write sorts keys (canonical); only written when
# something was added. Upgrade path: an order-preserving parser, if the reorder ever bites.
if [ -L "$S" ]; then say linked "$S -> $(readlink "$S") (managed there; left alone)"; exit 1; fi
perl - "$S" "$apply" "$URL" $GUARDS <<'PL'
use strict; use warnings; use JSON::PP;
my ($S, $apply, $url, @guards) = @ARGV;
my @deny = ('Bash(git add -A:*)', 'Bash(git add --all:*)', 'Bash(git add .:*)', 'Bash(git add -u:*)', 'Bash(git add :/:*)');
my $json = JSON::PP->new->utf8->pretty->canonical->indent_length(2);
my $left = 0;
sub say_ { printf "%-8s %s\n", @_; $left = 1 if $_[0] =~ /^(missing|legacy)$/ }
sub fix { say_($apply ? 'added' : 'missing', "$S $_[0]") }
sub hook { { type => 'command', command => qq(bash "\$CLAUDE_PROJECT_DIR/.agents/hooks/$_[0].sh") } }
sub write_s { open my $f, '>:raw', $S or die "$S: $!\n"; print $f $json->encode($_[0]); close $f or die "$S: $!\n" }

if (!-e $S) {
  unless ($apply) { say_ missing => $S; exit 1 }
  write_s({
    extraKnownMarketplaces => { 'agent-kit' => { source => { source => 'url', url => $url } } },
    enabledPlugins => { 'agent-kit@agent-kit' => JSON::PP::true },
    permissions => {
      allow => ['Bash(git status:*)', 'Bash(git diff:*)', 'Bash(git log:*)', 'Bash(git show:*)'],
      deny => [@deny],
    },
    hooks => { PreToolUse => [{ matcher => 'Bash', hooks => [map { hook($_) } @guards] }] },
  });
  say_ added => $S; exit 0;
}

my $j = eval { local $/; open my $f, '<:raw', $S or die; $json->decode(<$f>) };
ref $j eq 'HASH' or do { print STDERR "$S is not valid JSON — fix it by hand first\n"; exit 2 };
my $before = $json->encode($j);

# Marketplace + plugin. The marketplace was once called univates.br: carry its source over
# instead of guessing a URL, and leave the old key for the user — other plugins may use it.
my $mk = $j->{extraKnownMarketplaces} //= {};
if ($mk->{'agent-kit'}) { say_ ok => "$S extraKnownMarketplaces.agent-kit" }
else {
  my $old = $mk->{'univates.br'};
  $mk->{'agent-kit'} = { source => ($old && $old->{source}) || { source => 'url', url => $url } };
  fix('extraKnownMarketplaces.agent-kit');
}
my $ep = $j->{enabledPlugins} //= {};
if ($ep->{'agent-kit@agent-kit'}) { say_ ok => "$S enabledPlugins.agent-kit\@agent-kit" }
else {
  $ep->{'agent-kit@agent-kit'} = JSON::PP::true;
  delete $ep->{'agent-kit@univates.br'};
  fix('enabledPlugins.agent-kit@agent-kit');
}
for my $k ((sort keys %$mk), (sort keys %$ep)) {
  say_ legacy => "$S $k (old marketplace name; remove it if nothing else uses it)" if $k =~ /univates\.br/;
}

# deny entries: added one by one, whatever else the project denies stays.
my $dl = $j->{permissions}{deny} //= [];
for my $d (@deny) {
  next if grep { $_ eq $d } @$dl;
  push @$dl, $d; fix("permissions.deny $d");
}

# Hook registrations: a guard counts as registered if any PreToolUse command names it,
# however the project spelled the path. Missing ones join the first Bash group.
my $pre = $j->{hooks}{PreToolUse} //= [];
for my $g (@guards) {
  if (grep { index($_->{command} // '', "$g.sh") >= 0 } map { @{ $_->{hooks} || [] } } @$pre) {
    say_ ok => "$S hook $g"; next;
  }
  my ($grp) = grep { ($_->{matcher} // '') eq 'Bash' } @$pre;
  push @$pre, $grp = { matcher => 'Bash', hooks => [] } unless $grp;
  push @{ $grp->{hooks} }, hook($g);
  fix("hook $g");
}

# Unchanged data is never rewritten, so an in-sync file keeps its own formatting.
write_s($j) if $apply && $json->encode($j) ne $before;
exit $left;
PL
r=$?
case $r in 0|1) exit $((left | r)) ;; *) exit 2 ;; esac
