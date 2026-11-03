//! The extraction rules: which archive entries a receiver writes, and where
//! (SEC-1–3, UP-7). They decide; the driver does the writing, inside a
//! staging directory.

use std::collections::HashSet;
use std::fmt;

use super::cpio::Entry;

/// A validated relative path: one or more components, none empty, `.` or
/// `..`, and none containing a separator, NUL, control character or bidi
/// override. Built for Windows, components must also be names Windows
/// creates as given (see `is_windows_name`).
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct RelPath(Vec<String>);

/// Longest component and whole path accepted, in bytes.
const MAX_COMPONENT: usize = 255;
const MAX_PATH: usize = 1024;

impl RelPath {
    /// Parses an archive name or `FileBomPath`: `./a/b` or `a/b`. Absolute
    /// paths and `..` are refused (SEC-1).
    pub fn parse(name: &str) -> Result<Self, PathError> {
        let rest = name.strip_prefix("./").unwrap_or(name);
        if rest.is_empty() || name.len() > MAX_PATH {
            return Err(PathError(name.into()));
        }
        let components: Vec<String> = rest.split('/').map(String::from).collect();
        if components.iter().all(|c| is_component(c)) {
            Ok(RelPath(components))
        } else {
            Err(PathError(name.into()))
        }
    }

    /// A single component, such as a `FileName`.
    pub fn file_name(name: &str) -> Result<Self, PathError> {
        if is_component(name) && name.len() <= MAX_PATH {
            Ok(RelPath(vec![name.into()]))
        } else {
            Err(PathError(name.into()))
        }
    }

    pub fn components(&self) -> &[String] {
        &self.0
    }

    pub fn starts_with(&self, prefix: &RelPath) -> bool {
        self.0.starts_with(&prefix.0)
    }

    pub fn parent(&self) -> Option<RelPath> {
        (self.0.len() > 1).then(|| RelPath(self.0[..self.0.len() - 1].to_vec()))
    }

    pub fn last(&self) -> &str {
        self.0.last().unwrap()
    }
}

impl fmt::Display for RelPath {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0.join("/"))
    }
}

fn is_component(c: &str) -> bool {
    !c.is_empty()
        && c != "."
        && c != ".."
        && c.len() <= MAX_COMPONENT
        && !c
            .chars()
            .any(|ch| ch == '/' || ch == '\\' || ch.is_control() || is_bidi_control(ch))
        && (!cfg!(windows) || is_windows_name(c))
}

/// Bidi embeddings, overrides and isolates, which can make a name display as
/// something else (`photo\u{202e}gpj.exe` shows as `photoexe.jpg`). The
/// plain direction marks stay allowed: real names contain them.
fn is_bidi_control(ch: char) -> bool {
    matches!(ch, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
}

/// Whether Windows creates a file by this name as given. A `:` makes a
/// drive-relative path (`C:x`) or names an NTFS alternate data stream, the
/// device names open the device whatever the extension, and a trailing dot or
/// space is silently stripped.
fn is_windows_name(c: &str) -> bool {
    let stem = c.split('.').next().unwrap_or(c).trim_end_matches(' ');
    let stem = stem.to_ascii_uppercase();
    let port = stem
        .strip_prefix("COM")
        .or_else(|| stem.strip_prefix("LPT"));
    let device = matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || port.is_some_and(|n| {
            matches!(n, "\u{b9}" | "\u{b2}" | "\u{b3}")
                || (n.len() == 1 && n.as_bytes()[0].is_ascii_digit())
        });
    !device && !c.ends_with(['.', ' ']) && !c.contains(['<', '>', ':', '"', '|', '?', '*'])
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PathError(pub String);

impl fmt::Display for PathError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "unsafe path {:?}", self.0)
    }
}

impl std::error::Error for PathError {}

#[derive(Debug, Clone, Copy)]
pub struct Limits {
    /// Most entries in one archive.
    pub max_entries: u32,
    /// Most file data in one archive, uncompressed.
    pub max_total: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Limits {
            max_entries: 4096,
            max_total: 16 << 30,
        }
    }
}

/// What to do with an archive entry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Item {
    /// The `.` root entry: nothing to write.
    Root,
    Dir(RelPath),
    File(RelPath),
    /// An AppleDouble `._` sidecar holding a listed item's Finder metadata:
    /// read past its data, write nothing (UP-7a).
    Skip,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    Path(PathError),
    /// UP-7: not one of the items the `/Ask` listed.
    NotAsked(String),
    Duplicate(String),
    /// A symlink, device, FIFO or socket, or a file with hard links (SEC-1).
    Unsupported(String),
    TooManyEntries,
    TooLarge,
    BadRoot,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Path(e) => e.fmt(f),
            Error::NotAsked(name) => write!(f, "archive entry {name:?} wasn't in the /Ask"),
            Error::Duplicate(name) => write!(f, "archive entry {name:?} appears twice"),
            Error::Unsupported(name) => {
                write!(f, "archive entry {name:?} isn't a plain file or directory")
            }
            Error::TooManyEntries => f.write_str("archive has too many entries"),
            Error::TooLarge => f.write_str("archive is too large"),
            Error::BadRoot => f.write_str("bad archive root entry"),
        }
    }
}

impl std::error::Error for Error {}

impl From<PathError> for Error {
    fn from(e: PathError) -> Self {
        Error::Path(e)
    }
}

/// One item an accepted `/Ask` lists.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Allowed {
    pub path: RelPath,
    pub is_directory: bool,
}

/// Applies the rules to an archive's entries in order.
#[derive(Debug)]
pub struct Rules {
    allowed: Vec<Allowed>,
    limits: Limits,
    seen: HashSet<RelPath>,
    destinations: HashSet<RelPath>,
    entries: u32,
    total: u64,
}

impl Rules {
    pub fn new(allowed: Vec<Allowed>, limits: Limits) -> Self {
        Rules {
            allowed,
            limits,
            seen: HashSet::new(),
            destinations: HashSet::new(),
            entries: 0,
            total: 0,
        }
    }

    pub fn check(&mut self, entry: &Entry) -> Result<Item, Error> {
        self.entries += 1;
        if self.entries > self.limits.max_entries {
            return Err(Error::TooManyEntries);
        }
        if entry.name == "." || entry.name == "./" {
            if !entry.is_dir() || entry.size != 0 {
                return Err(Error::BadRoot);
            }
            return Ok(Item::Root);
        }
        let path = RelPath::parse(&entry.name)?;
        let unsupported = || Error::Unsupported(entry.name.clone());
        // SEC-1: plain files and directories only. A file with other links is
        // a hard link, whose data may be in another entry.
        if !(entry.is_file() && entry.nlink <= 1 || entry.is_dir() && entry.size == 0) {
            return Err(unsupported());
        }
        let listed = self
            .allowed
            .iter()
            .any(|a| path == a.path && a.is_directory == entry.is_dir());
        let wrapped_file = self
            .allowed
            .iter()
            .any(|a| !a.is_directory && a.path.components().len() == 2 && path == a.path);
        let wrapper = !listed
            && entry.is_dir()
            && self.allowed.iter().any(|a| {
                !a.is_directory
                    && a.path.components().len() == 2
                    && a.path.parent().as_ref() == Some(&path)
            });
        let item = if wrapper || !listed && entry.is_file() && self.is_sidecar(&path) {
            Item::Skip
        } else if wrapped_file && entry.is_file() {
            Item::File(RelPath::file_name(path.last())?)
        } else if listed || self.is_inside_directory(&path) {
            if entry.is_dir() {
                Item::Dir(path.clone())
            } else {
                Item::File(path.clone())
            }
        } else {
            return Err(Error::NotAsked(entry.name.clone()));
        };
        if !self.seen.insert(path) {
            return Err(Error::Duplicate(entry.name.clone()));
        }
        if let Item::File(destination) | Item::Dir(destination) = &item
            && !self.destinations.insert(destination.clone())
        {
            return Err(Error::Duplicate(entry.name.clone()));
        }
        self.total = self.total.saturating_add(entry.size);
        if self.total > self.limits.max_total {
            return Err(Error::TooLarge);
        }
        Ok(item)
    }

    /// Besides the listed items themselves, entries inside a listed directory
    /// are allowed.
    fn is_inside_directory(&self, path: &RelPath) -> bool {
        self.allowed
            .iter()
            .any(|a| a.is_directory && path.starts_with(&a.path) && *path != a.path)
    }

    /// `._name` next to an allowed `name`.
    fn is_sidecar(&self, path: &RelPath) -> bool {
        let Some(name) = path.last().strip_prefix("._") else {
            return false;
        };
        let Ok(mut target) = RelPath::file_name(name) else {
            return false;
        };
        if let Some(parent) = path.parent() {
            let mut components = parent.0;
            components.push(name.into());
            target = RelPath(components);
        }
        self.allowed
            .iter()
            .any(|a| target == a.path || a.is_directory && target.starts_with(&a.path))
    }
}

/// SEC-2: the `n`th alternative to `name` when it's taken, as
/// `photo (1).jpg`. The extension stays last; dotfiles keep their dot.
pub fn collision_name(name: &str, n: u32) -> String {
    match name.rfind('.') {
        Some(dot) if dot > 0 => format!("{} ({n}){}", &name[..dot], &name[dot..]),
        _ => format!("{name} ({n})"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::archive::cpio::{MODE_DIR, MODE_FILE};

    fn entry(name: &str, mode: u32, size: u64) -> Entry {
        Entry {
            name: name.into(),
            mode,
            size,
            nlink: 1,
            ino: 1,
            uid: 0,
            gid: 0,
            mtime: 0,
        }
    }

    fn rules(items: &[(&str, bool)]) -> Rules {
        Rules::new(
            items
                .iter()
                .map(|(p, d)| Allowed {
                    path: RelPath::parse(p).unwrap(),
                    is_directory: *d,
                })
                .collect(),
            Limits {
                max_entries: 10,
                max_total: 1000,
            },
        )
    }

    // spec: SEC-1
    #[test]
    fn refuses_unsafe_paths() {
        for name in [
            "/etc/x",
            "../x",
            "./../x",
            "a/../../x",
            "a//b",
            "./",
            "",
            "a/./b",
            "a\\b",
            "a\nb",
            "photo\u{202e}gpj.exe",
            "a/\u{2067}b",
        ] {
            assert!(RelPath::parse(name).is_err(), "accepted {name:?}");
        }
        assert!(RelPath::parse("\u{200f}\u{5e9}\u{5dc}\u{5d5}\u{5dd}.jpg").is_ok());
        assert_eq!(RelPath::parse("./a/b").unwrap().to_string(), "a/b");
        assert_eq!(RelPath::parse("a").unwrap().to_string(), "a");
    }

    // spec: SEC-1
    #[test]
    fn knows_names_windows_would_change() {
        for name in [
            "C:x",
            "a.txt:stream",
            "CON",
            "nul.txt",
            "Com1.jpg",
            "LPT9",
            "COM\u{b9}",
            "aux .txt",
            "a.",
            "a ",
            "a?b",
            "a*b",
            "a|b",
            "a\"b",
            "<a>",
        ] {
            assert!(!is_windows_name(name), "accepted {name:?}");
        }
        for name in ["IMG_0049.HEIC", "CONTRACT.pdf", "COM10", "a.b.c", ".hidden"] {
            assert!(is_windows_name(name), "refused {name:?}");
        }
    }

    // spec: SEC-1
    #[test]
    fn refuses_links_and_special_files() {
        let mut r = rules(&[("x", false)]);
        assert!(matches!(
            r.check(&entry("./x", 0o120777, 3)),
            Err(Error::Unsupported(_))
        ));
        assert!(matches!(
            r.check(&entry("./x", 0o020644, 0)),
            Err(Error::Unsupported(_))
        ));
        let mut hard = entry("./x", MODE_FILE | 0o644, 3);
        hard.nlink = 2;
        assert!(matches!(r.check(&hard), Err(Error::Unsupported(_))));
    }

    // spec: UP-7, UP-7a
    #[test]
    fn allows_only_what_the_ask_listed() {
        let mut r = rules(&[("a.txt", false), ("Folder", true)]);
        assert_eq!(r.check(&entry(".", MODE_DIR | 0o755, 0)), Ok(Item::Root));
        assert!(matches!(
            r.check(&entry("./a.txt", MODE_FILE | 0o644, 5)),
            Ok(Item::File(_))
        ));
        assert!(matches!(
            r.check(&entry("./Folder", MODE_DIR | 0o755, 0)),
            Ok(Item::Dir(_))
        ));
        assert!(matches!(
            r.check(&entry("./Folder/b/c.txt", MODE_FILE | 0o644, 5)),
            Ok(Item::File(_))
        ));
        assert_eq!(
            r.check(&entry("./._a.txt", MODE_FILE | 0o644, 5)),
            Ok(Item::Skip)
        );
        assert_eq!(
            r.check(&entry("./Folder/._c.txt", MODE_FILE | 0o644, 5)),
            Ok(Item::Skip)
        );
        assert!(matches!(
            r.check(&entry("./other", MODE_FILE | 0o644, 5)),
            Err(Error::NotAsked(_))
        ));
        assert!(matches!(
            r.check(&entry("./._other", MODE_FILE | 0o644, 5)),
            Err(Error::NotAsked(_))
        ));
        // A listed file arriving as a directory, and the reverse.
        let mut r = rules(&[("a", false), ("d", true)]);
        assert!(matches!(
            r.check(&entry("./a", MODE_DIR | 0o755, 0)),
            Err(Error::NotAsked(_))
        ));
        assert!(matches!(
            r.check(&entry("./d", MODE_FILE | 0o644, 0)),
            Err(Error::NotAsked(_))
        ));
        assert!(matches!(
            r.check(&entry("./a/x", MODE_FILE | 0o644, 0)),
            Err(Error::NotAsked(_))
        ));
    }

    #[test]
    fn refuses_duplicates() {
        let mut r = rules(&[("a", false)]);
        r.check(&entry("./a", MODE_FILE | 0o644, 1)).unwrap();
        assert!(matches!(
            r.check(&entry("a", MODE_FILE | 0o644, 1)),
            Err(Error::Duplicate(_))
        ));
    }

    #[test]
    fn wrapped_photos_are_flattened_without_allowing_other_entries_or_collisions() {
        let mut r = rules(&[("wrap-one/one.jpg", false), ("wrap-two/two.jpg", false)]);
        assert_eq!(
            r.check(&entry("./wrap-one", MODE_DIR | 0o755, 0)),
            Ok(Item::Skip)
        );
        assert_eq!(
            r.check(&entry("./wrap-one/one.jpg", MODE_FILE | 0o644, 3)),
            Ok(Item::File(RelPath::file_name("one.jpg").unwrap()))
        );
        assert_eq!(
            r.check(&entry("./wrap-one/._one.jpg", MODE_FILE | 0o644, 2)),
            Ok(Item::Skip)
        );
        assert_eq!(
            r.check(&entry("./wrap-two", MODE_DIR | 0o755, 0)),
            Ok(Item::Skip)
        );
        assert_eq!(
            r.check(&entry("./wrap-two/two.jpg", MODE_FILE | 0o644, 3)),
            Ok(Item::File(RelPath::file_name("two.jpg").unwrap()))
        );
        assert!(matches!(
            r.check(&entry("./other", MODE_DIR | 0o755, 0)),
            Err(Error::NotAsked(_))
        ));
        assert!(matches!(
            r.check(&entry("./wrap-one/other.jpg", MODE_FILE | 0o644, 1)),
            Err(Error::NotAsked(_))
        ));
        assert!(matches!(
            r.check(&entry("./wrap-one/one.jpg", MODE_FILE | 0o644, 1)),
            Err(Error::Duplicate(_))
        ));

        let mut r = rules(&[("a/photo.jpg", false), ("b/photo.jpg", false)]);
        r.check(&entry("./a/photo.jpg", MODE_FILE | 0o644, 1))
            .unwrap();
        assert!(matches!(
            r.check(&entry("./b/photo.jpg", MODE_FILE | 0o644, 1)),
            Err(Error::Duplicate(_))
        ));
        let mut r = rules(&[("a/photo.jpg", false)]);
        assert_eq!(
            r.check(&entry("./a/photo.jpg", MODE_FILE | 0o644, 1001)),
            Err(Error::TooLarge)
        );
        assert!(matches!(
            r.check(&entry("./a/photo.jpg", 0o120777, 1)),
            Err(Error::Unsupported(_))
        ));
    }

    // spec: SEC-3
    #[test]
    fn enforces_limits() {
        let mut r = rules(&[("d", true)]);
        assert_eq!(
            r.check(&entry("./d/big", MODE_FILE | 0o644, 1001)),
            Err(Error::TooLarge)
        );
        let mut r = rules(&[("d", true)]);
        for i in 0..10 {
            r.check(&entry(&format!("./d/{i}"), MODE_FILE | 0o644, 0))
                .unwrap();
        }
        assert_eq!(
            r.check(&entry("./d/x", MODE_FILE | 0o644, 0)),
            Err(Error::TooManyEntries)
        );
    }

    // spec: SEC-2
    #[test]
    fn names_collisions() {
        assert_eq!(collision_name("photo.jpg", 1), "photo (1).jpg");
        assert_eq!(collision_name("README", 2), "README (2)");
        assert_eq!(collision_name(".bashrc", 1), ".bashrc (1)");
    }
}
