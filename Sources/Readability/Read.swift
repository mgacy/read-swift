//
//  Readability.swift
//  Readability
//
//  Created by Shahaf Levi on 19/05/2019.
//  Copyright © 2019 Sl's Repository Ltd. All rights reserved.
//

/**
 * Arc90's Readability ported to Swift
 * Based on the PHP port of [Keyvan Minoukadeh](http://www.keyvan.net), http://fivefilters.org/content-only/, 2014-03-27.
 * Based on readability.js version 1.7.1 (without multi-page support)
 * ------------------------------------------------------
 * Original URL: http://lab.arc90.com/experiments/readability/js/readability.js
 * Arc90's project URL: http://lab.arc90.com/experiments/readability/
 * JS Source: http://code.google.com/p/arc90labs-readability
 *
 * Differences between the PHP port and the original
 * ------------------------------------------------------
 * Arc90's Readability is designed to run in the browser. It works on the DOM
 * tree (the parsed HTML) after the page's CSS styles have been applied and
 * Javascript code executed. This PHP port does not run inside a browser.
 * We use PHP's ability to parse HTML to build our DOM tree, but we cannot
 * rely on CSS or Javascript support. As such, the results will not always
 * match Arc90's Readability. (For example, if a web page contains CSS style
 * rules or Javascript code which hide certain HTML elements from display,
 * Arc90's Readability will dismiss those from consideration but our PHP port,
 * unable to understand CSS or Javascript, will not know any better.)
 *
 * Another significant difference is that the aim of Arc90's Readability is
 * to re-present the main content block of a given web page so users can
 * read it more easily in their browsers. Correct identification, clean up,
 * and separation of the content block is only a part of this process.
 * This PHP port is only concerned with this part, it does not include code
 * that relates to presentation in the browser - Arc90 already do
 * that extremely well, and for PDF output there"s FiveFilters.org"s
 * PDF Newspaper: http://fivefilters.org/pdf-newspaper/.
 *
 * Finally, this class contains methods that might be useful for developers
 * working on HTML document fragments. So without deviating too much from
 * the original code (which I don't want to do because it makes debugging
 * and updating more difficult), I've tried to make it a little more
 * developer friendly. You should be able to use the methods here on
 * existing DOMElement objects without passing an entire HTML document to
 * be parsed.
 */

import Foundation
import SwiftSoup

public class Readability {
    public var version = "1.7.1-without-multi-page"
    public var convertLinksToFootnotes = false
    public var revertForcedParagraphElements = true
    public var articleTitle: Element?
    public var articleContent: Element?
    public var dom: Document
    public var url: String? // optional - URL where HTML was retrieved
    public var html: String
    public var debug = false
    public var lightClean = true // preserves more content (experimental) added 2012-09-19
    public var canonical: String?

    public var allSpecialHandling = false // if true, overrides all special handling booleans
    public var githubSpecialHandling = false // perform special handling on github repos
    public var stackExchangeSpecialHandling = false // perform special functions on StackExchange pages
    public var acceptedAnswerOnly = false // on a stack site, only grab accepted answer
    public var includeAnswerComments = false // on a stack site, include comments in the output
    public var minimumAnswerUpvotes = 0 // only save answers with a minimum number of upvotes

    public var appleDeveloperSpecialHandling = false // perform special functions on StackExchange pages

    private var body: Element? //
    private var bodyCache: String? // Cache the body HTML in case we need to re-use it later

    private var flags = 7 // 1 | 2 | 4;   // Start with all flags set.
    let FLAG_STRIP_UNLIKELYS = 1
    let FLAG_WEIGHT_CLASSES = 2
    let FLAG_CLEAN_CONDITIONALLY = 4

    private var success = false // indicates whether we were able to extract or not

    /// Create instance of Readability.
    /// - Parameters:
    ///   - html: The HTML to parse.
    ///   - url: URL associated with HTML (used for footnotes).
    public init(html: String, url: String? = nil) throws {
        self.url = url

        // when converting code blocks containing highlight spans, whitespace surrounded by span tags can get stripped
        // This removes the surrounding span tags
        self.html = html.replacingOccurrences(of: #"<span[^>]*?>([\n\t ]+)</span>"#, with: "$1", options: .regularExpression)

        /* Turn all double <br>s into <p>s */
        self.html = self.html.replacingOccurrences(of: RegEx.replaceBrs, with: "</p><p>")
        self.html = self.html.replacingOccurrences(of: RegEx.replaceFonts, with: "<$1span>")

        if self.html.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            self.html = "<html></html>"
        }

        if let url {
            dom = try SwiftSoup.parse(self.html, url)
        } else {
            dom = try SwiftSoup.parse(self.html)
        }

        do {
            try cleanRougeTables()
        } catch {
            // FIXME: log error
            print(error)
        }
    }

    /// Special handling for StackExchange sites.
    public func stackOverflow() throws {
        guard dom.ownerDocument() != nil else {
            throw ReadabilityError.custom("No document associated with dom.")
        }

        try removeScripts(dom)

        let bodyElems = try dom.getElementsByTag("body").array()

        if bodyElems.count > 0 {
            if bodyCache == nil {
                bodyCache = try bodyElems[0].html()
            }

            if body == nil {
                let bodyHTML = try bodyElems[0].html()

                try body?.html(bodyHTML)
            }
        }

        try prepDocument()

        /* Build readability's DOM tree */
        let overlay = try dom.createElement("div")
        let innerDiv = try dom.createElement("div")

        var articleContent = try dom.createElement("div")

        // --- / Shared with `appleDeveloper()`

        let main = try dom.getElementsByClass("inner-content").first()!
        let title = try main.select("#question-header h1 a.question-hyperlink").first()!.getInnerText()

        let articleTitleh1 = try dom.createElement("h1")
        try articleTitleh1.text(title)

        let question = try main.select("#question")
        let questionContent = try question.select(".js-post-body").array()[0]
        let questionComments = try question.select(".js-post-comments-component .comments .comments-list .comment-body")

        try articleContent.append(questionContent.html())
        if includeAnswerComments {
            try articleContent.append("<hr>")
            try articleContent.append(questionComments.html())
        }

        let answersDiv = try main.select("#answers")
        let answersTitleEl = try answersDiv.select("#answers-header .answers-subheader h2").first()!
        let extraSpan = try answersTitleEl.select("span").last()!
        try extraSpan.remove()
        let answersTitle = try answersTitleEl.getInnerText()
        let acceptedAnswer = try answersDiv.select(".answer.accepted-answer")

        let otherAnswers = try answersDiv.select(".answer").not(".accepted-answer").array()

        if !acceptedAnswerOnly {
            try articleContent.append("<h2>\(answersTitle)</h2>")
        }

        if acceptedAnswer.array().count > 0 {
            let acceptedAnswerBody = try acceptedAnswer.array()[0].select(".js-post-body")
            let acceptedAnswerComments = try acceptedAnswer.array()[0].select(".comments .comments-list .comment-body")

            try articleContent.append("<h3>Accepted Answer</h3>")
            try articleContent.append(acceptedAnswerBody.html())
            if includeAnswerComments {
                try articleContent.append("<h4>Comments</h4>")
                try articleContent.append(acceptedAnswerComments.html())
            }
            try articleContent.append("<hr>")
        }

        if !acceptedAnswerOnly {
            if otherAnswers.count > 0 {
                try articleContent.append("<h3>All Answers</h3>")
                for answer in otherAnswers {
                    let upvotesEl = try answer.select(".js-vote-count").first()
                    let upvotes = upvotesEl != nil ? Int(try upvotesEl!.attr("data-value"))! : 0
                    if minimumAnswerUpvotes == 0 || upvotes >= minimumAnswerUpvotes {
                        try articleContent.append(try answer.select(".js-post-body").html())
                        if includeAnswerComments {
                            try articleContent.append("<h4>Comments</h4>")
                            try articleContent.append(try answer.select(".comments .comments-list .comment .comment-text").html())
                        }
                        try articleContent.append("<hr>")
                    }
                }
            }
        }

        if try articleContent.getInnerText() == "" {
            throw ReadabilityError.parsingFailed
        }

        try overlay.attr("id", "readOverlay")
        try innerDiv.attr("id", "readInner")

        /* Glue the structure of our document together. */
        try innerDiv.appendChild(articleTitleh1)
        try innerDiv.appendChild(articleContent)
        try overlay.appendChild(innerDiv)

        /* Clear the old HTML, insert the new content. */
        try body?.html("")
        try body?.appendChild(overlay)
        try body?.removeAttr("style")

        try postProcessContent(articleContent)

        // Set title and content instance variables
        articleTitle = articleTitleh1
        self.articleContent = articleContent
    }

    /// Special handling for developer.apple.com questions.
    public func appleDeveloper() throws {
        guard dom.ownerDocument() != nil else {
            throw ReadabilityError.custom("No document associated with dom.")
        }

        try removeScripts(dom)

        let bodyElems = try dom.getElementsByTag("body").array()

        if bodyElems.count > 0 {
            if bodyCache == nil {
                bodyCache = try bodyElems[0].html()
            }

            if body == nil {
                let bodyHTML = try bodyElems[0].html()

                try body?.html(bodyHTML)
            }
        }

        try prepDocument()

        /* Build readability's DOM tree */
        let overlay = try dom.createElement("div")
        let innerDiv = try dom.createElement("div")

        var articleContent = try dom.createElement("div")

        // --- / Shared with `stackOverflow()`

        // FIXME: guard here
        let main = try dom.select("#main-content .page").first()!
        let question = try main.select("#question-container").first()!
        let title = try question.select(".header h1.title").first()!.getInnerText()

        let articleTitleh1 = try dom.createElement("h1")
        try articleTitleh1.text(title)

        let questionContent = try question.select("section.question .content .column-right .post-content").array()[0]

        try articleContent.append(questionContent.html())
        try articleContent.append("<hr>")

        let otherAnswers = try main.select("#answers-list .content-post.answer").array()

        if otherAnswers.count > 0 {
            try articleContent.append("<h3>All Answers</h3>")
            for answer in otherAnswers {
                try articleContent.append(try answer.select(".content .column-right .post-content").html())

                try articleContent.append("<hr>")
            }
        }

        if try articleContent.getInnerText() == "" {
            throw ReadabilityError.parsingFailed
        }

        try overlay.attr("id", "readOverlay")
        try innerDiv.attr("id", "readInner")

        /* Glue the structure of our document together. */
        try innerDiv.appendChild(articleTitleh1)
        try innerDiv.appendChild(articleContent)
        try overlay.appendChild(innerDiv)

        /* Clear the old HTML, insert the new content. */
        try body?.html("")
        try body?.appendChild(overlay)
        try body?.removeAttr("style")

        try postProcessContent(articleContent)

        // Set title and content instance variables
        articleTitle = articleTitleh1
        self.articleContent = articleContent
    }

    /**
     * Get article title element
     * @return DOMElement
     */
    public func getTitle() -> Element? {
        articleTitle
    }

    /**
     * Get article content element
     * @return DOMElement
     */
    public func getContent() -> Element? {
        articleContent
    }

    public func cleanGitHubTable(table: Element) -> Element {
        return table
//         TODO: GitHub displays code files as tables instead of pre/code and it does NOT translate well
//         Need to get the innerText, but the SwiftSoup getInnerText method loses whitespace
        // The .text() method removes whitespace, so getInnerText has no chance to preserve it
//        var inner = getInnerTextWithWhitespace(table)
//        inner = inner.replacingOccurrences(of: #"((\n *){3}(?=\n))"#, with: "", options: .regularExpression)
//        inner = inner.replacingOccurrences(of: #"\t"#, with: "    ", options: .regularExpression)
//        inner = inner.replacingOccurrences(of: #"(?<=^|\n) {10}"#, with: "", options: .regularExpression)
//
//        let pre = try! dom.createElement("pre")
//        let block = try! dom.createElement("code")
//        try! block.text(inner)
//        try! pre.append(block.outerHtml())
//        return pre
    }

    /// Runs readability.
    ///
    /// Workflow:
    ///
    /// 1. Prep the document by removing script tags, css, etc.
    /// 2. Build readability's DOM tree.
    /// 3. Grab the article content from the current dom tree.
    /// 4. Replace the current DOM tree with the new one.
    /// 5. Read peacefully.
    public func start() throws {
        guard dom.ownerDocument() != nil else {
            throw ReadabilityError.custom("No document associated with dom.")
        }

        let headlinks = try dom.select("head > link[rel=canonical]")

        if headlinks.count > 0 {
            canonical = try headlinks.first()!.attr("href")
        }

//        if githubSpecialHandling || allSpecialHandling {
//             if canonical != nil && canonical!.hasPrefix("https://github.com") {
//                 let tables = try! dom.select(".repository-content table.highlight")
//                 for table in tables {
//                     try! table.replaceWith(cleanGitHubTable(table: table))
//                 }
//             }
//         }

        if stackExchangeSpecialHandling || allSpecialHandling {
            if try dom.getElementsByTag("body").array()[0].hasClass("question-page") {
                return try stackOverflow()
            }
        }

        if appleDeveloperSpecialHandling || allSpecialHandling {
            if canonical != nil && canonical!.hasPrefix("https://developer.apple.com") {
                return try appleDeveloper()
            }
        }

        try removeScripts(dom)

        let bodyElems = try dom.getElementsByTag("body").array()
        if bodyElems.count > 0 {
            if bodyCache == nil {
                bodyCache = try bodyElems[0].html()
            }

            if body == nil {
                let bodyHTML = try bodyElems[0].html()

                try body?.html(bodyHTML)
            }
        }

        try prepDocument()

        /* Build readability's DOM tree */
        let overlay = try dom.createElement("div")
        let innerDiv = try dom.createElement("div")
        let articleTitle = try getArticleTitle()
        var articleContent = try grabArticle()

        if articleContent == nil {
            success = false

            articleContent = try dom.createElement("div")
            try articleContent!.attr("id", "readability-content")
            try articleContent!.html("<p>Sorry, Readability was unable to parse this page for content.</p>")
        }

        try overlay.attr("id", "readOverlay")
        try innerDiv.attr("id", "readInner")

        /* Glue the structure of our document together. */
        if articleTitle != nil {
            try innerDiv.appendChild(articleTitle!)
        }

        try innerDiv.appendChild(articleContent!)
        try overlay.appendChild(innerDiv)

        /* Clear the old HTML, insert the new content. */
        try body?.html("")
        try body?.appendChild(overlay)
        try body?.removeAttr("style")

        try postProcessContent(articleContent!)

        // Set title and content instance variables
        self.articleContent = articleContent
        self.articleTitle = articleTitle
        if let h1s = try self.articleTitle?.select("h1") {
            if h1s.count == 1 {
                let h1 = h1s.first()!
                let articleTitle = try dom.createElement("h1")
                try articleTitle.text(h1.getInnerText())
                self.articleTitle = articleTitle
            }
        }
    }

    /**
     * Debug
     */
    private func dbg(msg: String) {
        if debug {
            print("* ", msg, "\n")
        }
    }

    /**
     * Run any post-process modifications to article content as necessary.
     *
     * @param DOMElement
     * @return void
     */
    public func postProcessContent(_ articleContent: Element) throws {
        // FIXME: remove forced unwrap
        if convertLinksToFootnotes && url!.matches("/wikipedia\\.org/") {
            try addFootnotes(articleContent)
        }
    }

    private func cleanRougeTables() throws {
        let rougeTables = try dom.getElementsByClass("rouge-table").array()
        if rougeTables.count > 0 {
            for table in rougeTables {
                let code = try table.getElementsByClass("rouge-code").array()[0]
                let content = try code.getElementsByTag("pre").array()[0].getInnerText()
                let parent = table.parent()
                try parent?.text(content)
            }
        }
    }

    /**
     * Get the article title as an H1.
     *
     * @return DOMElement
     */
    private func getArticleTitle() throws -> Element? {
        var curTitle = ""
        var origTitle = ""
        do {
            let titleEls = try dom.getElementsByTag("title")
            if titleEls.count > 0 {
                origTitle = try titleEls[0].getInnerText()
            }

            curTitle = origTitle

            // if curTitle.matches(#" [|\-–] "#) {
            //     curTitle = origTitle.replacingOccurrences(of: #"(.*?)[|\-–] .*"#, with: "$1", options: .regularExpression)

            //     if curTitle.split(separator: " ").count < 3 {
            //         curTitle = origTitle.replacingOccurrences(of: #".*?[|\-—](.*)$"#, with: "$1", options: .regularExpression)
            //     }
            // }
        }

        curTitle = curTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // if curTitle.split(separator: " ").count <= 3 {
        //     curTitle = origTitle
        // }

        curTitle = curTitle.replacingOccurrences(of: #"[’‘]"#, with: "'", options: .regularExpression)
        curTitle = curTitle.replacingOccurrences(of: #"[”“]"#, with: "\"", options: .regularExpression)
        curTitle = curTitle.replacingOccurrences(of: #"[–—]"#, with: "--", options: .regularExpression)

        if !curTitle.isEmpty {
            articleTitle = try dom.createElement("h1")
            try articleTitle?.html(curTitle)

            return articleTitle!
        } else {
            let h1s = try dom.getElementsByTag("h1")
            if h1s.count > 0 {
                if h1s.count > 1 {
                    origTitle = try h1s[1].getInnerText()
                } else {
                    origTitle = try h1s.first()!.getInnerText()
                }
                curTitle = origTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                articleTitle = try dom.createElement("h1")
                try articleTitle?.html(curTitle)

                return articleTitle
            } else {
                return nil
            }
        }
    }

    /**
     * Prepare the HTML document for readability to scrape it.
     * This includes things like stripping javascript, CSS, and handling terrible markup.
     *
     * @return void
     **/
    public func prepDocument() throws {
        /**
         * In some cases a body element can't be found (if the HTML is totally hosed for example)
         * so we create a new body node and append it to the document.
         */
        if body == nil {
            body = try dom.createElement("body")
            try dom.ownerDocument()?.appendChild(body!)
        }

        try body?.attr("id", "readabilityBody")

        /* Remove all style tags in head */
        let styleTags = try dom.getElementsByTag("style").array()
        for tag in styleTags {
            try tag.parent()?.removeChild(tag)
        }

        // Remove aria-hidden elements
        let hiddenTags = try dom.getElementsByAttribute("aria-hidden")
        for tag in hiddenTags {
            try tag.parent()?.removeChild(tag)
        }

        /* Turn all double br"s into p"s */
        /* Note, this is pretty costly as far as processing goes. Maybe optimize later. */
        // document.body.innerHTML = document.body.innerHTML.replace(readability.regexps.replaceBrs, "</p><p>").replace(readability.regexps.replaceFonts, "<$1span>");
        // We do this in the constructor for PHP as that's when we have raw HTML - before parsing it into a DOM tree.
        // Manipulating innerHTML as it's done in JS is not possible in PHP.
    }

    /**
     * For easier reading, convert this document to have footnotes at the bottom rather than inline links.
     * @see http://www.roughtype.com/archives/2010/05/experiments_in.php
     *
     * @return void
     **/
    public func addFootnotes(_ articleContent: Element?) throws {
        let footnotesWrapper = try dom.createElement("div")
        try footnotesWrapper.attr("id", "readability-footnotes")
        try footnotesWrapper.html("<h3>References</h3>")

        let articleFootnotes = try dom.createElement("ol")
        try articleFootnotes.attr("id", "readability-footnotes-list")
        try footnotesWrapper.appendChild(articleFootnotes)

        let articleLinks = try articleContent?.getElementsByTag("a").array()

        var linkCount = 0

        // FIXME: remove forced unwrap
        for articleLink in articleLinks! {
            let footnoteLink = articleLink.copy(clone: articleLink) as? Element
            // cloneNode(true)
            let refLink = try dom.createElement("a")
            let footnote = try dom.createElement("li")
            var linkDomain = URLComponents(string: try footnoteLink!.attr("href"))!.host
            // @parse_url(footnoteLink.attr("href"), PHP_URL_HOST)

            if linkDomain == nil, let url {
                linkDomain = URLComponents(string: url)!.host
                // @parse_url(self.url, PHP_URL_HOST)
            }

            let linkText = try articleLink.getInnerText()

            if try articleLink.attr("class").range(of: "readability-DoNotFootnote") != nil {
                continue
            }

            linkCount += 1

            // Add a superscript reference after the article link
            try refLink.attr("href", "#readabilityFootnoteLink-\(linkCount)")
            try refLink.html("<small><sup>[\(linkCount)]</sup></small>")
            try refLink.attr("class", "readability-DoNotFootnote")
            try refLink.attr("style", "color: inherit;")

            // TODO: does this work or should we use DOMNode.isSameNode()?
            if articleLink.parent()?.lastElementSibling() == articleLink {
                try articleLink.parent()?.appendChild(refLink)
            } else {
                let index = refLink.siblingIndex
                try articleLink.parent()?.insertChildren(index, [articleLink.nextSibling()!])
                // articleLink.parent()?.insertBefore(refLink, articleLink.nextSibling)
            }

            try articleLink.attr("style", "color: inherit; text-decoration: none;")
            try articleLink.attr("name", "readabilityLink-\(linkCount)")

            try footnote.html("<small><sup><a href=#readabilityLink-\(linkCount)\" title=\"Jump to Link in Article\">^</a></sup></small>")

            try footnoteLink!.html(footnoteLink!.attr("title") != "" ? footnoteLink!.attr("title") : linkText)
            try footnoteLink!.attr("name", "readabilityFootnoteLink-\(linkCount)")

            try footnote.appendChild(footnoteLink!)

            if let linkDomain {
                try footnote.html(footnote.html() + "<small>(\(linkDomain))</small>")
            }

            try articleFootnotes.appendChild(footnote)
        }

        if linkCount > 0 {
            try articleContent?.appendChild(footnotesWrapper)
        }
    }

    /**
     * Prepare the article node for display. Clean out any inline styles,
     * iframes, forms, strip extraneous <p> tags, etc.
     *
     * @param DOMElement
     * @return void
     */
    public func prepArticle(_ articleContent: Element) throws {
        try articleContent.cleanStyles()
        try killBreaks(articleContent)

        if revertForcedParagraphElements {
            try articleContent.revertReadabilityStyledElements()
        }

        /* Clean out junk from the article content */
        try cleanConditionally(articleContent, tag: "form")
        try articleContent.clean(tag: "object")
        try articleContent.clean(tag: "h1")

        /**
         * If there is only one h2, they are probably using it
         * as a header and not a subheader, so remove it since we already have a header.
         ***/
        if !lightClean && (try! articleContent.getElementsByTag("h2").array().count == 1) {
            try articleContent.clean(tag: "h2")
        }

        try articleContent.clean(tag: "iframe")

        try articleContent.cleanHeaders(getClassWeight: flagIsActive(flag: FLAG_WEIGHT_CLASSES))

        /* Do these last as the previous stuff may have removed junk that will affect these */
        try cleanConditionally(articleContent, tag: "table")
        try cleanConditionally(articleContent, tag: "ul")
        try cleanConditionally(articleContent, tag: "div")

        /* Remove extra paragraphs */
        let articleParagraphs = try articleContent.getElementsByTag("p").array()

        for article in articleParagraphs {
            let imgCount = try article.getElementsByTag("img").array().count
            let embedCount = try article.getElementsByTag("embed").array().count
            let objectCount = try article.getElementsByTag("object").array().count
            let iframeCount = try article.getElementsByTag("iframe").array().count

            if imgCount == 0 && embedCount == 0 && objectCount == 0 && iframeCount == 0 && (try! article.getInnerText(normalizeSpaces: false)) == "" {
                try article.parent()?.removeChild(article)
            }
        }

        do {
            try articleContent.html(articleContent.html().replacingOccurrences(of: "/<br[^>]*>\\s*<p/i", with: "<p"))
        } catch let error {
            self.dbg(msg: "Cleaning innerHTML of breaks failed. This is an IE strict-block-elements bug. Ignoring.: \(error)")
        }
    }

    /**
     * Initialize a node with the readability object. Also checks the
     * className/id for special names to add to its score.
     *
     * @param Element
     * @return void
     **/
    private func initializeNode(_ node: Element) throws {
        // var readability = try! self.dom.attr("readability", "\(0)")
        var contentScore = 0
        // readability.value = 0 // this is our contentScore
        // node.setAttributeNode(readability)
        try node.attr("readability", "\(0)")

        switch node.tagName().uppercased() { // unsure if strtoupper is needed, but using it just in case
        case "DIV":
            contentScore += 5
            break

        case "PRE", "TD", "BLOCKQUOTE":
            contentScore += 3
            break

        case "ADDRESS", "OL", "UL", "DL", "DD", "DT", "LI", "FORM":
            contentScore -= 3
            break

        case "H1", "H2", "H3", "H4", "H5", "H6", "TH":
            contentScore -= 5
            break
        default:
            break
        }

        if flagIsActive(flag: FLAG_WEIGHT_CLASSES) {
            contentScore += try node.getClassWeight()
        }

        try node.attr("readability", "\(contentScore)")
    }

    /***
     * grabArticle - Using a variety of metrics (content score, classname, element types), find the content that is
     *               most likely to be the stuff a user wants to read. Then return it wrapped up in a div.
     *
     * @return DOMElement
     **/
    private func grabArticle(_ doc: Element? = nil) throws -> Element? {
        var page = doc

        let stripUnlikelyCandidates = flagIsActive(flag: FLAG_STRIP_UNLIKELYS)

        if doc == nil {
            page = dom
        }

        let allElements = try page?.getAllElements().array()

        /**
         * First, node prepping. Trash nodes that look cruddy (like ones with the class name "comment", etc), and turn divs
         * into P tags where they have been used inappropriately (as in, where they contain no other block level elements.)
         *
         * Note: Assignment from index for performance. See http://www.peachpit.com/articles/article.aspx?p=31567&seqNum=5
         * TODO: Shouldn't this be a reverse traversal?
         **/
        // var node: Element? = nil

        var nodesToScore: [Element] = []

        for node in allElements! {
            // for ($nodeIndex=$targetList->length-1; $nodeIndex >= 0; $nodeIndex--) {
            let tagName = node.tagName().uppercased()

            /* Remove unlikely candidates */
            if stripUnlikelyCandidates {
                let unlikelyMatchString = try node.attr("class") + node.attr("id")

                if unlikelyMatchString.matches(RegEx.unlikelyCandidates) && !unlikelyMatchString.matches(RegEx.okMaybeItsACandidate) && tagName != "BODY" {
                    dbg(msg: "Removing unlikely candidate - \(unlikelyMatchString)")

                    try node.parent()?.removeChild(node)

                    continue
                }
            }

            if tagName == "P" || tagName == "TD" || tagName == "PRE" {
                nodesToScore.append(node)
            }

            /* Turn all divs that don"t have children block level elements into p"s */
            if tagName == "DIV" {
                if !((try node.html()).matches(RegEx.divToPElements)) {
                    let newNode = try dom.createElement("p")

                    do {
                        try newNode.html(node.html())
                        try node.parent()?.replaceChild(newNode, node)
                        nodesToScore.append(node) // or $newNode?
                    } catch let error {
                        self.dbg(msg: "Could not alter div to p, reverting back to div.: \(error)")
                    }
                } else {
                    /* EXPERIMENTAL */
                    // TODO: change these p elements back to text nodes after processing
                    for childNode in node.getChildNodes() {
                        if Int(childNode.nodeName()) == 3 { // XML_TEXT_NODE
                            // self.dbg("replacing text node with a p tag with the same content.");
                            let p = try dom.createElement("p")
                            try p.html(childNode.nodeName())
                            try p.attr("style", "display: inline;")
                            try p.attr("class", "readability-styled")
                            try childNode.parent()?.replaceChild(p, childNode)
                        }
                    }
                }
            }
        }

        /**
         * Loop through all paragraphs, and assign a score to them based on how content-y they look.
         * Then add their score to their parent node.
         *
         * A score is determined by things like number of commas, class names, etc. Maybe eventually link density.
         **/
        var candidates: [Element] = []

        for pt in nodesToScore {
            let parentNode = pt.parent()
            // $grandParentNode = $parentNode ? $parentNode->parentNode : null;
            let grandParentNode = parentNode == nil ? nil : parentNode!.parent()
            let innerText = try pt.getInnerText()

            if parentNode == nil || parentNode!.tagName().isEmpty {
                continue
            }

            /* If this paragraph is less than 25 characters, don't even count it. */
            if innerText.count < 25 {
                continue
            }

            /* Initialize readability data for the parent. */
            if !parentNode!.hasAttr("readability") {
                try initializeNode(parentNode!)
                candidates.append(parentNode!)
            }

            /* Initialize readability data for the grandparent. */
            if let grandParentNode, !grandParentNode.hasAttr("readability") {
                try initializeNode(grandParentNode)
                candidates.append(grandParentNode)
            }

            var contentScore = 0

            /* Add a point for the paragraph itself as a base. */
            contentScore += 1

            /* Add points for any commas within this paragraph */
            contentScore += innerText.split(separator: ",").count

            /* For every 100 characters in this paragraph, add another point. Up to 3 points. */
            contentScore += min(Int(floor(Double(innerText.count / 100))), 3)

            /* Add the score to the parent. The grandparent gets half. */
            var parentCurrentScore = Int(0)
            var grandParentCurrentScore = Int(0)
            if parentNode != nil {
                parentCurrentScore = Int(try parentNode!.attr("readability"))!
            }
            if grandParentNode != nil {
                grandParentCurrentScore = Int(try grandParentNode!.attr("readability"))!
            }

            parentCurrentScore += contentScore

            try parentNode!.attr("readability", String(parentCurrentScore))

            if grandParentNode != nil {
                grandParentCurrentScore += contentScore / 2
                try grandParentNode!.attr("readability", String(grandParentCurrentScore))
            }
        }

        /**
         * After we've calculated scores, loop through all of the possible candidate nodes we found
         * and find the one with the highest score.
         **/
        var topCandidate: Element?

        for cl in candidates {
            /**
             * Scale the final candidates score based on link density. Good content should have a
             * relatively small link density (5% or less) and be mostly unaffected by this operation.
             **/
            let readability = try cl.attr("readability")

            let value = Float(readability)! * (1 - (try cl.getLinkDensity()))

            try cl.attr("readability", String(value))

            dbg(msg: "Candidate: \(cl.tagName()) (\(try cl.attr("class")): \(try cl.attr("id"))) with score \(readability)")

            let topCandidateScore = try topCandidate?.attr("readability")

            if topCandidate == nil || Int(readability)! > Int(Float(topCandidateScore!)!) {
                topCandidate = cl
            }
        }

        /**
         * If we still have no top candidate, just use the body as a last resort.
         * We also have to copy the body node so it is something we can modify.
         **/
        if topCandidate === nil || topCandidate?.tagName().uppercased() == "BODY" {
            topCandidate = try dom.createElement("div")

            if page! is Document {
                if page?.ownerDocument() == nil {
                    // we don't have a body either? what a mess! :)
                } else {
                    try topCandidate?.html((page?.ownerDocument()?.html())!)
                    try page?.ownerDocument()?.html("")
                    try page?.ownerDocument()?.appendChild(topCandidate!)
                }
            } else {
                try topCandidate?.html((page?.html())!)
                try page?.html("")
                try page?.appendChild(topCandidate!)
            }

            try initializeNode(topCandidate!)
        }

        /**
         * Now that we have the top candidate, look through its siblings for content that might also be related.
         * Things like preambles, content split by ads that we removed, etc.
         **/
        let articleContent = try dom.createElement("div")
        try articleContent.attr("id", "readability-content")

        let siblingScoreThreshold = max(10, Double(try topCandidate!.attr("readability"))! * 0.2)
        var siblingNodes: [Node]? = topCandidate?.parent()?.getChildNodes()

        if siblingNodes == nil {
            siblingNodes = []
        }

        for siblingNode in siblingNodes! {
            var append = false

            try dbg(msg: "Looking at sibling node: \(siblingNode.nodeName()) \((siblingNode.hasAttr("readability")) ? (" with score " + siblingNode.attr("readability")) : ""))")

            // dbg("Sibling has score " . ($siblingNode->readability ? siblingNode.readability.contentScore : "Unknown"));

            if siblingNode === topCandidate {
                // or if ($siblingNode->isSameNode($topCandidate))
                append = true
            }

            var contentBonus: Double = 0
            /* Give a bonus if sibling nodes and top candidates have the example same classname */
            if try siblingNode.attr("class") == topCandidate!.attr("class") && topCandidate!.attr("class") != "" {
                contentBonus += Double(try topCandidate!.attr("readability"))! * 0.2
            }

            if try siblingNode.hasAttr("readability") && (Double(siblingNode.attr("readability"))! + contentBonus) >= siblingScoreThreshold {
                append = true
            }

            if siblingNode.nodeName().uppercased() == "P" {
                let linkDensity = try (siblingNode as! Element).getLinkDensity()
                let nodeContent = try (siblingNode as! Element).getInnerText()
                let nodeLength = nodeContent.count

                if nodeLength > 80 && linkDensity < 0.25 {
                    append = true
                } else if nodeLength < 80 && linkDensity == 0 && nodeContent.matches("/\\.( |$)/") {
                    append = true
                }
            }

            if append {
                dbg(msg: "Appending node: \(siblingNode.nodeName())")

                var nodeToAppend: Element?

                let sibNodeName = siblingNode.nodeName().uppercased()
                if sibNodeName != "DIV" && sibNodeName != "P" {
                    /* We have a node that isn"t a common block level element, like a form or td tag. Turn it into a div so it doesn"t get filtered out later by accident. */

                    dbg(msg: "Altering siblingNode of \(sibNodeName) to div.")

                    nodeToAppend = try dom.createElement("div")

                    do {
                        try nodeToAppend?.attr("id", siblingNode.attr("id"))
                        try nodeToAppend?.html(siblingNode.outerHtml())
                    } catch let error {
                        self.dbg(msg: "Could not alter siblingNode to div, reverting back to original. \(error)")

                        nodeToAppend = siblingNode as? Element
                    }
                } else {
                    nodeToAppend = siblingNode as? Element
                }

                /* To ensure a node does not interfere with readability styles, remove its classnames */
                try nodeToAppend?.removeAttr("class")

                /* Append sibling and subtract from our list because it removes the node when you append to another node */
                try articleContent.appendChild(nodeToAppend!)
            }
        }

        /**
         * So we have all of the content that we need. Now we clean it up for presentation.
         **/
        try prepArticle(articleContent)

        /**
         * Now that we've gone through the full algorithm, check to see if we got any meaningful content.
         * If we didn't, we may need to re-run grabArticle with different flags set. This gives us a higher
         * likelihood of finding the content, and the sieve approach gives us a higher likelihood of
         * finding the -right- content.
         **/
        if try articleContent.getInnerText(normalizeSpaces: false).count < 250 {
            // TODO: find out why element disappears sometimes, e.g. for this URL http://www.businessinsider.com/6-hedge-fund-etfs-for-average-investors-2011-7
            // in the meantime, we check and create an empty element if it's not there.
            if body?.getChildNodes() == nil {
                body = try dom.createElement("body")
            }

            try body?.html(bodyCache!)

            if flagIsActive(flag: FLAG_STRIP_UNLIKELYS) {
                removeFlag(flag: FLAG_STRIP_UNLIKELYS)
                return try grabArticle(body)
            } else if flagIsActive(flag: FLAG_WEIGHT_CLASSES) {
                removeFlag(flag: FLAG_WEIGHT_CLASSES)
                return try grabArticle(body!)
            } else if flagIsActive(flag: FLAG_CLEAN_CONDITIONALLY) {
                removeFlag(flag: FLAG_CLEAN_CONDITIONALLY)
                return try grabArticle(body)
            }
            /* else {
             	return false
             } */
        }

        return articleContent
    }

    /**
     * Remove script tags from document
     *
     * @param DOMElement
     * @return void
     */
    public func removeScripts(_ doc: Document) throws {
        let scripts = try doc.getElementsByTag("script").array()

        for script in scripts {
            try script.parent()?.removeChild(script)
        }

        let noscripts = try doc.getElementsByTag("noscript").array()

        for script in noscripts {
            try script.parent()?.removeChild(script)
        }
    }

    /**
     * Remove extraneous break tags from a node.
     *
     * @param DOMElement $node
     * @return void
     */
    public func killBreaks(_ node: Element) throws {
        html = try node.html()

        html = html.replacingOccurrences(of: RegEx.killBreaks, with: "<br />")

        try node.html(html)
    }

    /**
     * Clean an element of all tags of type "tag" if they look fishy.
     * "Fishy" is an algorithm based on content length, classnames,
     * link density, number of images & embeds, etc.
     *
     * @param DOMElement $e
     * @param string $tag
     * @return void
     */
    public func cleanConditionally(_ e: Element, tag: String) throws {
        if !flagIsActive(flag: FLAG_CLEAN_CONDITIONALLY) {
            return
        }

        let tagsList = try e.getElementsByTag(tag).array()

        /**
         * Gather counts for other typical elements embedded within.
         * Traverse backwards so we can remove nodes at the same time without effecting the traversal.
         *
         * TODO: Consider taking into account original contentScore here.
         */
        for tag in tagsList {
            let weight = flagIsActive(flag: FLAG_WEIGHT_CLASSES) ? try tag.getClassWeight() : 0

            let contentScore = (tag.hasAttr("readability")) ? try Int(Float(tag.attr("readability"))!) : 0

            dbg(msg: "Cleaning Conditionally \(tag.tagName()) (\(try tag.attr("class"))/#\(try tag.attr("id")))" + "\(tag.hasAttr("readability") ? " with score  \(try tag.attr("readability"))" : "")")

            if weight + contentScore < 0 {
                try tag.parent()?.removeChild(tag)
            } else if try tag.getCharCount(s: ",") < 10 {
                /**
                 * If there are not very many commas, and the number of
                 * non-paragraph elements is more than paragraphs or other ominous signs, remove the element.
                 **/
                let p = try tag.getElementsByTag("p").array().count
                let img = try tag.getElementsByTag("img").array().count
                let li = try tag.getElementsByTag("li").array().count - 100
                let input = try tag.getElementsByTag("input").array().count
                let a = try tag.getElementsByTag("a").array().count

                var embedCount = 0
                var embeds = try tag.getElementsByTag("embed").array()

                for embed in embeds {
                    if try embed.attr("src").matches(RegEx.video) {
                        embedCount += 1
                    }
                }

                embeds = try tag.getElementsByTag("iframe").array()

                for iframe in embeds {
                    if try iframe.attr("src").matches(RegEx.video) {
                        embedCount += 1
                    }
                }

                let linkDensity = try tag.getLinkDensity()
                let contentLength = try tag.getInnerText().count
                var toRemove = false

                if lightClean {
                    dbg(msg: "Light clean...")

                    if img > p && img > 4 {
                        dbg(msg: " more than 4 images and more image elements than paragraph elements")

                        toRemove = true
                    } else if li > p && tag.tagName() != "ul" && tag.tagName() != "ol" {
                        dbg(msg: "too many <li> elements, and parent is not <ul> or <ol>")

                        toRemove = true
                    } else if Double(input) > floor(Double(p / 3)) {
                        dbg(msg: "too many <input> elements")

                        toRemove = true
                    } else if contentLength < 25 && (embedCount == 0 && (img == 0 || img > 2)) {
                        dbg(msg: "content length less than 10 chars, 0 embeds and either 0 images or more than 2 images")

                        toRemove = true
                    } else if weight < 25 && linkDensity > 0.2 {
                        dbg(msg: "weight smaller than 25 and link density above 0.2")

                        toRemove = true
                    } else if a > 2 && weight >= 25 && linkDensity > 0.5 {
                        dbg(msg: "more than 2 links and weight above 25 but link density greater than 0.5")

                        toRemove = true
                    } else if embedCount > 3 {
                        dbg(msg: "more than 3 embeds")

                        toRemove = true
                    }
                } else {
                    dbg(msg: "Standard clean...")

                    if img > p {
                        dbg(msg: "more image elements than paragraph elements")

                        toRemove = true
                    } else if li > p && tag.tagName() != "ul" && tag.tagName() != "ol" {
                        dbg(msg: "too many <li> elements, and parent is not <ul> or <ol>")

                        toRemove = true
                    } else if Double(input) > floor(Double(p / 3)) {
                        dbg(msg: "too many <input> elements")

                        toRemove = true
                    } else if contentLength < 25 && (img == 0 || img > 2) {
                        dbg(msg: "content length less than 25 chars and 0 images, or more than 2 images")

                        toRemove = true
                    } else if weight < 25 && linkDensity > 0.2 {
                        dbg(msg: "weight smaller than 25 and link density above 0.2")

                        toRemove = true
                    } else if weight >= 25 && linkDensity > 0.5 {
                        dbg(msg: "weight above 25 but link density greater than 0.5")

                        toRemove = true
                    } else if embedCount == 1 && contentLength < 75 || embedCount > 1 {
                        dbg(msg: "1 embed and content length smaller than 75 chars, or more than one embed")

                        toRemove = true
                    }
                }

                if toRemove {
                    try tag.parent()?.removeChild(tag)
                }
            }
        }
    }

    public func flagIsActive(flag: Int) -> Bool {
        return (flags & flag) > 0
    }

    public func addFlag(flag: Int) {
        flags = flags | flag
    }

    public func removeFlag(flag: Int) {
        flags = flags & ~flag
    }
}

// MARK: - Backwards Compatiblity
public extension Readability {
    /**
     * Get the inner text of a node.
     * This also strips out any excess whitespace to be found.
     *
     * @param DOMElement $
     * @param boolean $normalizeSpaces (default: true)
     * @return string
     **/
    func getInnerText(_ e: Element, normalizeSpaces: Bool = true) -> String {
        try! e.getInnerText(normalizeSpaces: normalizeSpaces)
    }

    /**
     * Get the number of times a string $s appears in the node $e.
     *
     * @param DOMElement $e
     * @param string - what to count. Default is ","
     * @return number (integer)
     **/
    func getCharCount(_ e: Element, s: String = ",") -> Int {
        try! e.getInnerText().rangesOfString(s: s).count
    }

    /**
     * Remove the style attribute on every $e and under.
     *
     * @param DOMElement $e
     * @return void
     */
    func cleanStyles(_ e: Element) {
        try! e.cleanStyles()
    }

    /**
     * Get the density of links as a percentage of the content
     * This is the amount of text that is inside a link divided by the total text in the node.
     *
     * @param DOMElement $e
     * @return number (float)
     */
    func getLinkDensity(_ e: Element) -> Float {
        try! e.getLinkDensity()
    }

    /**
     * Get an elements class/id weight. Uses regular expressions to tell if this
     * element looks good or bad.
     *
     * @param DOMElement $e
     * @return number (Integer)
     */
    func getClassWeight(_ e: Element) -> Int {
        if !flagIsActive(flag: FLAG_WEIGHT_CLASSES) {
            return 0
        }
        return try! e.getClassWeight()
    }

    /**
     * Clean a node of all elements of type "tag".
     * (Unless it's a youtube/vimeo video. People love movies.)
     *
     * Updated 2012-09-18 to preserve youtube/vimeo iframes
     *
     * @param DOMElement $e
     * @param string $tag
     * @return void
     */
    func clean(_ e: Element, tag: String) {
        try! e.clean(tag: tag)
    }

    /**
     * Clean out spurious headers from an Element. Checks things like classnames and link density.
     *
     * @param DOMElement $e
     * @return void
     */
    func cleanHeaders(_ e: Element) {
        try! e.cleanHeaders(getClassWeight: flagIsActive(flag: FLAG_WEIGHT_CLASSES))
    }
}
