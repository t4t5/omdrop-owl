//! The `/Discover` and `/Ask` plist bodies (§6.3, §6.4).
//!
//! Decoding is lenient where the spec lets it be: unknown keys are ignored,
//! and both `/Ask` shapes are accepted. Encoding always produces the shape
//! iOS 18 needs (ASK-7).

use std::fmt;

use super::plist::{Dict, Value};

/// `StatusCode` values in a `/Discover` response.
pub const STATUS_EVERYONE: i64 = 100;
pub const STATUS_CONTACT: i64 = 200;
pub const STATUS_NOT_A_CONTACT: i64 = 401;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error(pub &'static str);

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "bad message: {}", self.0)
    }
}

impl std::error::Error for Error {}

fn dict(value: &Value) -> Result<&Dict, Error> {
    value.as_dict().ok_or(Error("not a dictionary"))
}

fn string(d: &Dict, key: &str) -> Result<Option<String>, Error> {
    match d.get(key) {
        None => Ok(None),
        Some(Value::String(s)) => Ok(Some(s.clone())),
        Some(_) => Err(Error("expected a string")),
    }
}

fn data(d: &Dict, key: &str) -> Result<Option<Vec<u8>>, Error> {
    match d.get(key) {
        None => Ok(None),
        Some(Value::Data(b)) => Ok(Some(b.clone())),
        Some(_) => Err(Error("expected data")),
    }
}

fn insert_opt(d: &mut Dict, key: &str, value: Option<Value>) {
    if let Some(value) = value {
        d.insert(key.into(), value);
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DiscoverRequest {
    pub sender_record: Option<Vec<u8>>,
    pub sender_computer_name: Option<String>,
    pub sender_model_name: Option<String>,
    pub sender_id: Option<String>,
}

impl DiscoverRequest {
    pub fn from_plist(value: &Value) -> Result<Self, Error> {
        let d = dict(value)?;
        Ok(DiscoverRequest {
            sender_record: data(d, "SenderRecordData")?,
            sender_computer_name: string(d, "SenderComputerName")?,
            sender_model_name: string(d, "SenderModelName")?,
            sender_id: string(d, "SenderID")?,
        })
    }

    pub fn to_plist(&self) -> Value {
        let mut d = Dict::new();
        insert_opt(
            &mut d,
            "SenderRecordData",
            self.sender_record.clone().map(Value::Data),
        );
        insert_opt(
            &mut d,
            "SenderComputerName",
            self.sender_computer_name.clone().map(Value::String),
        );
        insert_opt(
            &mut d,
            "SenderModelName",
            self.sender_model_name.clone().map(Value::String),
        );
        insert_opt(
            &mut d,
            "SenderID",
            self.sender_id.clone().map(Value::String),
        );
        Value::Dict(d)
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DiscoverResponse {
    pub status_code: Option<i64>,
    /// Present exactly when the sender may list this receiver (DISC-1).
    pub receiver_computer_name: Option<String>,
    pub receiver_model_name: Option<String>,
    /// UTF-8 JSON (DISC-3).
    pub receiver_media_capabilities: Option<Vec<u8>>,
    pub receiver_record: Option<Vec<u8>>,
}

impl DiscoverResponse {
    pub fn from_plist(value: &Value) -> Result<Self, Error> {
        let d = dict(value)?;
        Ok(DiscoverResponse {
            status_code: d.get("StatusCode").and_then(Value::as_integer),
            receiver_computer_name: string(d, "ReceiverComputerName")?,
            receiver_model_name: string(d, "ReceiverModelName")?,
            receiver_media_capabilities: data(d, "ReceiverMediaCapabilities")?,
            receiver_record: data(d, "ReceiverRecordData")?,
        })
    }

    pub fn to_plist(&self) -> Value {
        let mut d = Dict::new();
        insert_opt(&mut d, "StatusCode", self.status_code.map(Value::Integer));
        insert_opt(
            &mut d,
            "ReceiverComputerName",
            self.receiver_computer_name.clone().map(Value::String),
        );
        insert_opt(
            &mut d,
            "ReceiverModelName",
            self.receiver_model_name.clone().map(Value::String),
        );
        insert_opt(
            &mut d,
            "ReceiverMediaCapabilities",
            self.receiver_media_capabilities.clone().map(Value::Data),
        );
        insert_opt(
            &mut d,
            "ReceiverRecordData",
            self.receiver_record.clone().map(Value::Data),
        );
        Value::Dict(d)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AskFile {
    pub name: String,
    /// A UTI such as `public.jpeg`.
    pub file_type: String,
    /// Uncompressed size. Required in the iOS 18 shape, absent in the legacy
    /// one.
    pub size: Option<u64>,
    /// The entry's path in the `/Upload` archive, `./<name>`.
    pub bom_path: String,
    pub is_directory: bool,
}

/// What the `/Ask` offers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Offer {
    Files(Vec<AskFile>),
    Urls(Vec<String>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AskRequest {
    /// `TransferID.id`, the UUID that ties `/Upload` to this request (UP-9).
    /// `None` for the legacy shape.
    pub transfer_id: Option<String>,
    /// The key of the iOS 18 shape's `TransferType` dict, such as `files`
    /// or `links` (§6.4). Encoding derives it
    /// from the offer when it's `None`.
    pub transfer_type: Option<String>,
    pub sender_computer_name: String,
    pub sender_model_name: String,
    pub sender_id: String,
    pub bundle_id: String,
    pub sender_record: Option<Vec<u8>>,
    pub file_icon: Option<Vec<u8>>,
    pub offer: Offer,
    /// The whole request as received, for logs ([`Value::describe`]).
    /// Empty for one built to send.
    pub described: String,
}

impl AskRequest {
    /// Decodes either shape. Required fields that are missing default to
    /// empty, so an odd sender still gets a prompt; only `Files`/`Items`
    /// decide whether the request makes sense.
    pub fn from_plist(value: &Value) -> Result<Self, Error> {
        let d = dict(value)?;
        let transfer_id = match d.get("TransferID") {
            None => None,
            Some(Value::Dict(t)) => Some(string(t, "id")?.ok_or(Error("TransferID has no id"))?),
            // A plain string doesn't get a prompt on iOS 18 (ASK-7), but
            // there's no reason to refuse it here.
            Some(Value::String(s)) => Some(s.clone()),
            Some(_) => return Err(Error("bad TransferID")),
        };
        let transfer_type = match d.get("TransferType") {
            Some(Value::Dict(t)) => t.keys().next().cloned(),
            _ => None,
        };
        let files = match d.get("Files") {
            None => Vec::new(),
            Some(Value::Array(files)) => files.iter().map(ask_file).collect::<Result<_, _>>()?,
            Some(_) => return Err(Error("Files is not an array")),
        };
        let items = match d.get("Items") {
            None => Vec::new(),
            Some(Value::Array(items)) => items
                .iter()
                .map(|i| {
                    i.as_str()
                        .map(String::from)
                        .ok_or(Error("Items holds a non-string"))
                })
                .collect::<Result<_, _>>()?,
            Some(_) => return Err(Error("Items is not an array")),
        };
        let offer = match (files.is_empty(), items.is_empty()) {
            (false, true) => Offer::Files(files),
            (true, false) => Offer::Urls(items),
            (true, true) => return Err(Error("nothing offered")),
            (false, false) => return Err(Error("both files and URLs offered")),
        };
        Ok(AskRequest {
            transfer_id,
            transfer_type,
            sender_computer_name: string(d, "SenderComputerName")?.unwrap_or_default(),
            sender_model_name: string(d, "SenderModelName")?.unwrap_or_default(),
            sender_id: string(d, "SenderID")?.unwrap_or_default(),
            bundle_id: string(d, "BundleID")?.unwrap_or_default(),
            sender_record: data(d, "SenderRecordData")?,
            file_icon: data(d, "FileIcon")?,
            offer,
            described: value.describe(),
        })
    }

    /// The iOS 18 shape (ASK-7), the only one senders send. The legacy
    /// shape is only decoded.
    pub fn to_plist(&self) -> Value {
        let mut d = Dict::new();
        if let Some(id) = &self.transfer_id {
            d.insert(
                "TransferID".into(),
                Value::Dict(Dict::from([("id".into(), id.clone().into())])),
            );
        }
        // `links` for a URL share, as iOS sends it (§6.4).
        let kind = match (&self.transfer_type, &self.offer) {
            (Some(kind), _) => kind.as_str(),
            (None, Offer::Files(_)) => "files",
            (None, Offer::Urls(_)) => "links",
        };
        d.insert(
            "TransferType".into(),
            Value::Dict(Dict::from([(kind.into(), Value::Dict(Dict::new()))])),
        );
        d.insert(
            "SenderComputerName".into(),
            self.sender_computer_name.clone().into(),
        );
        d.insert(
            "SenderModelName".into(),
            self.sender_model_name.clone().into(),
        );
        d.insert("SenderID".into(), self.sender_id.clone().into());
        d.insert("BundleID".into(), self.bundle_id.clone().into());
        d.insert("ConvertMediaFormats".into(), false.into());
        insert_opt(
            &mut d,
            "SenderRecordData",
            self.sender_record.clone().map(Value::Data),
        );
        insert_opt(&mut d, "FileIcon", self.file_icon.clone().map(Value::Data));
        let (files, items) = match &self.offer {
            Offer::Files(files) => (files.as_slice(), &[][..]),
            Offer::Urls(urls) => (&[][..], urls.as_slice()),
        };
        let files = files
            .iter()
            .map(|f| {
                let mut e = Dict::new();
                e.insert("FileName".into(), f.name.clone().into());
                e.insert("FileType".into(), f.file_type.clone().into());
                e.insert("FileBomPath".into(), f.bom_path.clone().into());
                e.insert("FileIsDirectory".into(), f.is_directory.into());
                e.insert(
                    "FileSize".into(),
                    Value::Integer(f.size.unwrap_or(0) as i64),
                );
                e.insert("ShouldConvertMediaFormats".into(), false.into());
                Value::Dict(e)
            })
            .collect();
        d.insert("Files".into(), Value::Array(files));
        d.insert(
            "Items".into(),
            Value::Array(items.iter().map(|u| u.clone().into()).collect()),
        );
        Value::Dict(d)
    }
}

fn ask_file(value: &Value) -> Result<AskFile, Error> {
    let d = dict(value)?;
    let name = string(d, "FileName")?.ok_or(Error("file without a FileName"))?;
    let bom_path = string(d, "FileBomPath")?.unwrap_or_else(|| format!("./{name}"));
    let size = match d.get("FileSize") {
        None => None,
        Some(Value::Integer(n)) if *n >= 0 => Some(*n as u64),
        Some(_) => return Err(Error("bad FileSize")),
    };
    let is_directory = match d.get("FileIsDirectory") {
        None => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(Error("bad FileIsDirectory")),
    };
    Ok(AskFile {
        file_type: string(d, "FileType")?.unwrap_or_else(|| "public.data".into()),
        name,
        size,
        bom_path,
        is_directory,
    })
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AskResponse {
    pub receiver_computer_name: String,
    pub receiver_model_name: String,
}

impl AskResponse {
    pub fn to_plist(&self) -> Value {
        Value::Dict(Dict::from([
            (
                "ReceiverComputerName".into(),
                self.receiver_computer_name.clone().into(),
            ),
            (
                "ReceiverModelName".into(),
                self.receiver_model_name.clone().into(),
            ),
        ]))
    }
}
