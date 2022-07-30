#!/usr/bin/env raku
my $date-fmt = { sprintf "%02d/%02d/%04d", .day, .month, .year };

enum Status (
  'KO', # Not downloaded/uploaded yet
  'DL', # Downloaded
  'UP', # Uploaded
);

subset FormattedDate of Str where /^\d ** 2 '/' \d ** 2 '/' \d ** 4$/;

constant TWITCH_VIDEO_PREFIX = 'https://www.twitch.tv/videos/';
subset StreamUrl of Str where /^ $(TWITCH_VIDEO_PREFIX)? \d+ $/;

sub stream-id(StreamUrl $url --> Int()) {
  if my $match = $url.match(/$(TWITCH_VIDEO_PREFIX)/) {
    $match.replace-with('')
  } else {
    $url
  }
}

sub stream-url(Int $id --> StreamUrl) {
  "$(TWITCH_VIDEO_PREFIX)$id"
}

class Line {
  has Status $.status is rw;
  has Int $.id;
  has Str $.streamer;
  has FormattedDate $.date;

  submethod parse(Line:U: Str $line, Int $no --> Line:D) {
    my @fields = $line.split(' ');
    die "Invalid number of fields {+@fields} on line $no" if @fields != 4;
    my ($status, $id, $streamer, $date) = @fields;
    Line.new(status => Status::{$status}, id => +$id, :$streamer, :$date);
  }

  submethod serialize(Line:D: --> Str) {
    "$!status $!id $!streamer $!date"
  }
}

sub load {
  my @lines = lines slurp 'Wrath_Classic_Archive_Project';
  @lines.map: { Line.parse($_, $++) };
}

my Line @data = load;

sub save(--> Nil) {
 spurt 'Wrath_Classic_Archive_Project', @data.map(*.serialize).join("\n"); 
}

sub beep { print 7.chr }


#| Adds a line like 'KO 1540376552 Avizura 24/07/2022'
multi MAIN('archive', StreamUrl $url, Str $streamer, FormattedDate :$date = $date-fmt(Date.today)) {
  my Int $stream-id = stream-id($url);
  with @data.first(*.id == $stream-id) {
    say "Streamer #$stream-id from {.streamer} already registered ({.status}).";
    return;
  }

  my $line = Line.new(status => KO, id => $stream-id, :$streamer, :$date);
  @data.push: $line;
  save;

  say "Starting download...";
  my $name = "video-{$streamer}-{$stream-id}.\%(ext)s";
  my $proc = Proc::Async.new: 'yt-dlp', '--cookies-from-browser', 'firefox', '-o', $name, stream-url($stream-id);
  await $proc.start;

  $line.status = DL;
  save;
  say "Downloaded.";
}

multi MAIN('upload', StreamUrl $url) {
  my Int $stream-id = stream-id($url);
  with @data.first(*.id == $stream-id) {
    .status = UP;
    save;
    say "Marked as uploaded!";
  } else {
    say "No such stream registered for download.";
  }
}

multi MAIN('to-upload') {
  my @to-upload = @data.grep(*.status == DL);
  if @to-upload {
    say "Found $(+@to-upload) videos to be uploaded.";
    for @to-upload {
      say "$(tc .streamer) [Twitch VOD] $(.date) -- $(.id).mp4";
    }
  } else {
    say "No video to be uploaded.";
  }
}
