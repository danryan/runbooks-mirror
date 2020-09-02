local removeBlankLines(str) =
  std.strReplace(str, '\n\n', '\n');

local chomp(str) =
  if std.isString(str) then
    std.rstripChars(str, '\n')
  else
    std.assertEqual(str, { __assert__: 'str should be a string value' });

local indent(str, spaces) =
  std.strReplace(removeBlankLines(chomp(str)), '\n', '\n' + std.repeat(' ', spaces));

local unwrapText(str) =
  local lines = std.split(str, '\n');
  local linesTrimmed = std.map(function(l) std.rstripChars(l, ' \t'), lines);
  local linesJoined = std.foldl(
    function(memo, line)
      local memoLast = std.length(memo) - 1;
      local prevItem = memo[memoLast];
      if line == '' || prevItem == '' then
        memo + [line]
      else
        // Join onto previous line
        memo[:memoLast] + [prevItem + ' ' + line],
    linesTrimmed[1:],
    linesTrimmed[:1]
  );
  std.join('\n', linesJoined);

{
  removeBlankLines(str):: removeBlankLines(str),
  chomp(str):: chomp(str),
  indent(str, spaces):: indent(str, spaces),
  unwrapText(str):: unwrapText(str),
}
