#!/usr/bin/env raku
my $date-fmt = { sprintf "%02d/%02d/%04d", .day, .month, .year };

enum Status (
  'KO', # Started downloading
  'DL', # Downloaded
  'UP', # Uploaded
);

subset FormattedDate of Str where /^\d ** 2 '/' \d ** 2 '/' \d ** 4$/;

constant TWITCH_VIDEO_PREFIX = 'https://www.twitch.tv/videos/';
subset StreamUrl of Str where /^ $(TWITCH_VIDEO_PREFIX)? \d+ '?filter=archives&sort=time'? $/;

sub stream-id(StreamUrl $orig-url --> Int()) {
  my $url = $orig-url.split('?')[0];
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
  my @lines = lines trim slurp 'Wrath_Classic_Archive_Project';
  @lines.map: { Line.parse($_, $++) };
}

my Line @data = load;

sub save(--> Nil) {
 spurt 'Wrath_Classic_Archive_Project', @data.map(*.serialize).join("\n"); 
}

sub beep { print 7.chr }


#| Adds a line like 'KO 1540376552 Avizura 24/07/2022'
multi MAIN('archive', Str $streamer, StreamUrl $url, FormattedDate $date = $date-fmt(Date.today)) {
  my Int $stream-id = stream-id($url);
  with @data.first(*.id == $stream-id) {
    say "Stream #$stream-id from {.streamer} already registered ({.status}).";
    return;
  }

  my $line = Line.new(status => KO, id => $stream-id, :$streamer, :$date);
  @data.push: $line;
  say "Added stream #$stream-id to the list.";
  save;
}

sub download(Line $stream where *.status == KO) {
  say "Starting download of stream {$stream.id} by {$stream.streamer} on {$stream.date}...";
  my $name = "video-{$stream.streamer}-{$stream.id}.\%(ext)s";
  my $proc = Proc::Async.new: 'yt-dlp', '--cookies-from-browser', 'firefox', '-o', $name, stream-url($stream.id);
  await $proc.start;

  $stream.status = DL;
  save;
  say "Downloaded.";
}

multi MAIN($dl where 'dl'|'download', 'first') {
  with @data.first(*.status == KO) -> $stream {
    download($stream);
  } else {
    say "No stream to download.";
  }
}

multi MAIN($dl where 'dl'|'download', 'all') {
  for @data.grep(*.status == KO) -> $stream {
    download($stream);
  }
  say "Done";
}

multi MAIN('download', StreamUrl $url) {
  my Int $stream-id = stream-id($url);
  with @data.first(*.id == $stream-id) -> $stream {
    if $stream.status != KO {
      say "Stream #{$stream-id} is in status $stream.status().";
      return;
    }
    download($stream);
  } else {
    say "Stream not found: #{$stream-id}.";
  }
}

multi MAIN('upload', StreamUrl $url) {
  my Int $stream-id = stream-id($url);
  with @data.first(*.id == $stream-id) -> $stream {
    if $stream.status != DL {
      say "Stream #$stream-id is marked as $stream.status()";
      return;
    }
    $stream.status = UP;
    save;

    say "Marked as uploaded!";
    my @files = dir(test => /:i ^ 'video-' $($stream.streamer) '-' $($stream.id) '.' .+ $/);
    given @files {
      when 0 { say "Could not find a file to move" }
      when 1 {
        move @files[0], "uploaded/@files[0]";
        say "Moved @files[0] to uploaded/";
      }
      default {
        say "Multiple files found matching the video pattern {$stream.id}:";
        for @files -> $file {
          say " - $file";
        }
      }
    }
  } else {
    say "No such stream registered for download.";
  }
}

sub listing(Status $status) {
  my @to-upload = @data.grep(*.status == $status);
  if @to-upload {
    say "Found $(+@to-upload) videos in state {$status}.";
    for @to-upload {
      say "$(tc .streamer) [Twitch VOD] $(.date) -- $(.id).mp4";
    }
  } else {
    say "No video in status {$status}.";
  }
}

multi MAIN('to', $up where 'upload'|'up') {
  listing(DL);
}

multi MAIN('to', 'do') {
  listing(KO);
}
