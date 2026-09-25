# Pictures With Captions

A picture standing alone in a paragraph gets the caption its Markdown already
carries - the title in quotes, or the alt text if there is no title:

![A build, end to end](assets/pipeline.png "How a book is built")

The alt text is still the alt text. A screen reader gets *A build, end to end*
and a sighted reader gets *How a book is built*, which is the point of writing
both.

A picture with no title falls back to its alt text:

![The same picture, captioned by its alt text](assets/pipeline.png)

An image inside a sentence is part of the sentence and is left alone - this one
![an icon](assets/pipeline.png "Not a caption") keeps its place in the line.

A book with no title and no alt text said what it wanted, and gets nothing:

![](assets/pipeline.png)
